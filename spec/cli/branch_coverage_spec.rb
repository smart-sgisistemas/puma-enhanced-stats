# frozen_string_literal: true

require "puma/enhanced/stats/cli/resource_attribution"
require "puma/enhanced/stats/cli/runner"
require "puma/enhanced/stats/cli/frame_renderer"
require "puma/enhanced/stats/cli/screen_manager"
require "puma/enhanced/stats/cli/top_renderer"
require "puma/enhanced/stats/cli/summary_renderer"
require "puma/enhanced/stats/cli/request_table"
require "puma/enhanced/stats/cli/worker_renderer"
require "puma/enhanced/stats/cli/cgroup_memory"
require "puma/enhanced/stats/cli/process_sampler"
require "puma/enhanced/stats/cli/user_config"
require "puma/enhanced/stats/cli/terminal"
require "puma/enhanced/stats/cli/keyboard"
require "puma/enhanced/stats/cli/format"
require "puma/enhanced/stats/cli/alert_level"
require "puma/enhanced/stats/cli/metric_line"
require "puma/enhanced/stats/cli/request_field_catalog"
require "puma/enhanced/stats/cli/severity_sorter"
require "puma/enhanced/stats/cli/footer_renderer"
require "puma/enhanced/stats/cli/stub_server"

RSpec.describe "CLI branch coverage" do
  it "exercises remaining branch paths" do
    ra = Puma::Enhanced::Stats::CLI::ResourceAttribution
    cold = Puma::Enhanced::Stats::CLI::HostMetrics::Snapshot.new(
      load: nil,
      cpu: Puma::Enhanced::Stats::CLI::HostMetrics::CPU.new(usr: 0, sys: 0, idle: 100, usage: 0.1),
      memory: Puma::Enhanced::Stats::CLI::HostMetrics::Usage.new(used: 1, total: 10, ratio: 0.1),
      swap: Puma::Enhanced::Stats::CLI::HostMetrics::Usage.new(used: 0, total: 1, ratio: 0),
      memory_limit_hint: nil
    )
    expect(ra.send(:top_suffix, cold, :ok, 10, :cpu)).to be_nil
    expect(ra.send(:top_suffix, cold, :ok, 10, :mem)).to be_nil
    expect(ra.send(:top_suffix, cold, :warn, 10, :cpu)).to be_nil
    expect(ra.send(:summary_label, 10, 100, 0)).to be_nil

    partial = Puma::Enhanced::Stats::CLI::HostMetrics::Snapshot.new(
      load: nil, cpu: nil, memory: nil, swap: nil, memory_limit_hint: nil
    )
    result = ra.compute(host: partial, puma_pids: [1], process_by_pid: {}, degraded: false)
    expect(result.level).to eq :ok

    Puma::Enhanced::Stats::CLI::UserConfig.load(StringIO.new("badkey\n").path) rescue nil
    path = File.join(Dir.tmpdir, "pes-#{Process.pid}")
    File.write path, "badkey\n"
    expect(Puma::Enhanced::Stats::CLI::UserConfig.load path).to eq({})
    File.delete path

    allow(Puma::Enhanced::Stats::CLI::Terminal).to receive(:tty?).and_return true
    allow($stdout).to receive(:tty?).and_return true
    allow($stdout).to receive :print
    Puma::Enhanced::Stats::CLI::Terminal.enter_alternate_screen!

    allow(Puma::Enhanced::Stats::CLI::Terminal).to receive(:tty?).and_return true
    console = instance_double(IO, getch: "x")
    allow(console).to receive(:respond_to?).with(:raw).and_return true
    allow(console).to receive(:raw).with(min: 1, time: 0).and_yield
    allow(IO).to receive(:console).and_return console
    allow(IO).to receive(:select).and_return [[console]]
    expect(Puma::Enhanced::Stats::CLI::Keyboard.read(deadline: Time.now.to_i + 1)).to eq "x"

    expect(Puma::Enhanced::Stats::CLI::Format.elapsed(nil, "2026-01-01T00:00:00Z")).to match /\d/
    expect(Puma::Enhanced::Stats::CLI::Format.collected_clock("2026-01-01T12:00:00Z")).to eq "12:00:00"

    expect(Puma::Enhanced::Stats::CLI::AlertLevel.for_ratio 0.95).to eq :crit
    expect(Puma::Enhanced::Stats::CLI::AlertLevel.for_dropped 0).to eq :ok

    colors = Puma::Enhanced::Stats::CLI::Colors.new(Puma::Enhanced::Stats::CLI::Options.new.tap { |o| o.no_color = true })
    expect(Puma::Enhanced::Stats::CLI::MetricLine.new(
      label: "x", value: "1", bar: "#", suffix: "stale 1", colors: colors
    ).render.join).to include "stale"
    expect(Puma::Enhanced::Stats::CLI::MetricLine.new(
      label: "y", value: "2", bar: "#", suffix: :warn, colors: nil
    ).render.join).to include "WARN"

    Puma::Enhanced::Stats::CLI::CgroupMemory.reset!
    stub_const "RUBY_PLATFORM", "linux"
    allow(File).to receive(:file?).and_return false
    allow(File).to receive(:readlines).with("/proc/meminfo").and_return(["Cached: 1 kB\n"])
    allow(File).to receive(:readlines).with("/proc/stat").and_return(["cpu  1 0 0 0 0 0 0 0 0 0\n"])
    expect(Puma::Enhanced::Stats::CLI::CgroupMemory.total_bytes).to be_nil

    allow(Puma::Enhanced::Stats::CLI::ProcessSampler).to receive(:runner).and_return(
      instance_double(Puma::Enhanced::Stats::CLI::ProcessSampler::Runner, ps_batch: "", ps_outsiders: "bad\n")
    )
    expect(Puma::Enhanced::Stats::CLI::ProcessSampler.sample_all([{ "pid" => 1 }], master_pid: nil).size).to eq 1

    expect(Puma::Enhanced::Stats::CLI::RequestFieldCatalog.discover [
      { "id" => "1", "started_at" => "t", "elapsed" => "1s", "session" => {} }
    ]).to include "elapsed"

    items = [{ "id" => "1", "started_at" => "t", "elapsed_ms" => 1, "method" => "GET", "path_info" => "/x", "session" => {} }]
    table = Puma::Enhanced::Stats::CLI::RequestTable.new([items.first, items.first], inner_width: 120, display_mode: "inline", offset: 0)
    expect(table.render(max_items: 1).join "\n").to include "more requests"
    stack = Puma::Enhanced::Stats::CLI::RequestTable.new(
      [{ "id" => "1", "started_at" => "t", "path_info" => "short", "session" => {} }],
      inner_width: 40, display_mode: "stack", offset: 0
    )
    expect(stack.render(max_items: 1).join "\n").not_to include "rep…"

    workers = [{ "index" => 0, "pid" => 1, "synced_at" => "2026-01-01T00:00:00Z", "puma" => { "backlog" => 0 }, "requests" => { "items" => [] } }]
    expect(Puma::Enhanced::Stats::CLI::SeveritySorter.sort_workers(
      workers, process_by_pid: {}, interval: 5, mode: "cluster", collected_at: "2026-01-01T00:00:10Z"
    ).size).to eq 1

    host = Puma::Enhanced::Stats::CLI::HostMetrics::Snapshot.new(
      load: [0.1, 0.2, 0.3],
      cpu: Puma::Enhanced::Stats::CLI::HostMetrics::CPU.new(usr: 1, sys: 1, idle: 98, usage: 0.5),
      memory: Puma::Enhanced::Stats::CLI::HostMetrics::Usage.new(used: 1, total: 2, ratio: 0.5),
      swap: Puma::Enhanced::Stats::CLI::HostMetrics::Usage.new(used: 1, total: 2, ratio: 0.5),
      memory_limit_hint: nil
    )
    options = Puma::Enhanced::Stats::CLI::Options.new.tap { |o| o.no_color = true }
    colors = Puma::Enhanced::Stats::CLI::Colors.new options
    bar = Puma::Enhanced::Stats::CLI::Bar.new colors
    attribution = ra.compute(host: host, puma_pids: [1], process_by_pid: {
      1 => Puma::Enhanced::Stats::CLI::ProcessSampler::Sample.new(pid: 1, cpu_percent: 1, mem_percent: 1, rss_bytes: 1)
    })
    top = Puma::Enhanced::Stats::CLI::TopRenderer.new(options, bar, host: host, attribution: attribution)
    budget = Puma::Enhanced::Stats::CLI::LayoutBudget.new(40, 80, options, worker_count: 1)
    expect(top.render_top budget).to include "Swap"

    summary = Puma::Enhanced::Stats::CLI::SummaryRenderer.new bar, colors
    payload = mixed_payload.merge("max_threads_total" => 0, "requests_in_flight" => 0)
    expect(summary.render(payload, budget, attribution: attribution)).to include "SUMMARY"

    options.show_outsiders = true
    budget = Puma::Enhanced::Stats::CLI::LayoutBudget.new(40, 120, options, worker_count: 2, layout: "stacked")
    attribution.result.outsiders.replace([
      Puma::Enhanced::Stats::CLI::ProcessSampler::Outsider.new(pid: 9, cpu_percent: 1, mem_percent: 1, rss_bytes: 1, command: "x")
    ])
    frame = Puma::Enhanced::Stats::CLI::FrameRenderer.new options, budget, bar, colors
    view = Puma::Enhanced::Stats::CLI::PayloadView.wrap(
      mixed_payload.merge("_cli" => { "worker_check_interval_seconds" => 0 })
    )
    frame.send(:prepare_workers, view, {})
    frame.send(:worker_sections, mixed_payload, {}, Puma::Enhanced::Stats::CLI::ScrollState.new, 5, "compact")

    manager = Puma::Enhanced::Stats::CLI::ScreenManager.new(options)
    options.modal = :unknown
    expect(manager.render_modal budget).to be_nil
    options.modal = :help
    manager.handle("p", scroll: Puma::Enhanced::Stats::CLI::ScrollState.new, payload: mixed_payload)
    options.modal = nil
    manager.handle("[", scroll: Puma::Enhanced::Stats::CLI::ScrollState.new, payload: { "worker_status" => [] })

    runner = Puma::Enhanced::Stats::CLI::Runner.new
    opts = runner.send :parse, ["--filter", "bad", "--no-rc"]
    expect(opts.filters).to eq({})
    runner.instance_variable_set(:@options, Puma::Enhanced::Stats::CLI::Options.new.tap { |o| o.no_top = true })
    runner.instance_variable_set(:@sync_interval, 5)
    runner.instance_variable_set(:@fetcher, instance_double(Puma::Enhanced::Stats::CLI::Fetcher, master_pid: nil, worker_check_interval: 5))
    runner.instance_variable_set(:@scroll, Puma::Enhanced::Stats::CLI::ScrollState.new)
    runner.instance_variable_set :@screen, manager
    allow(Puma::Enhanced::Stats::CLI::Terminal).to receive(:size).and_return [40, 80]
    allow(Puma::Enhanced::Stats::CLI::ProcessSampler).to receive(:sample_all).and_return({})
    allow(runner).to receive(:render_frame).and_return "frame\n"
    runner.send :print_frame, mixed_payload, 5

    allow(Puma::Enhanced::Stats::CLI::Terminal).to receive(:tty?).and_return false
    allow(Puma::Enhanced::Stats::CLI::Terminal).to receive(:resize_pending).and_return true
    allow(runner).to receive(:monotonic).and_return 1000, 1000, 1006
    allow(runner).to receive :print_frame
    allow(runner).to receive(:loop).and_yield
    allow(Puma::Enhanced::Stats::CLI::Keyboard).to receive(:refresh?).and_return false
    fetcher = instance_double(Puma::Enhanced::Stats::CLI::Fetcher, fetch: mixed_payload, master_pid: nil, worker_check_interval: 5)
    runner.instance_variable_set :@sync_interval, 5
    runner.instance_variable_set :@fetcher, fetcher
    runner.instance_variable_set(:@options, Puma::Enhanced::Stats::CLI::Options.new)
    expect(runner.send :run_watch, mixed_payload).to eq 0

    options = Puma::Enhanced::Stats::CLI::Options.new.tap { |o| o.no_color = true }
    renderer = Puma::Enhanced::Stats::CLI::WorkerRenderer.new options, bar, colors
    worker = mixed_workers.first.merge("puma" => mixed_workers.first["puma"].merge("max_threads" => 0))
    renderer.render(
      worker, budget, process_by_pid: {},
      collected_at: mixed_view.collected_at, interval: 5, mode: "cluster",
      scroll: Puma::Enhanced::Stats::CLI::ScrollState.new
    )

    expect(Puma::Enhanced::Stats::CLI::FooterRenderer.new.render(
      Puma::Enhanced::Stats::CLI::Options.new.tap { |o| o.save_message = "saved" },
      budget, refresh_interval: 5, layout_hint: nil
    )).to include "saved"

    server = Puma::Enhanced::Stats::CLI::StubServer.new port: 0, token: "t", payload: {}
    socket = instance_double(TCPSocket, close: nil)
    allow(socket).to receive(:gets).and_return "GET /enhanced-stats?token=wrong HTTP/1.1\r\n", "\r\n"
    allow(socket).to receive(:write) { |body| expect(body).to include "403" }
    server.send :handle, socket
  end
end
