# frozen_string_literal: true

require "puma/enhanced/stats/cli/metric_line"
require "puma/enhanced/stats/cli/cgroup_memory"
require "puma/enhanced/stats/cli/resource_attribution"
require "puma/enhanced/stats/cli/request_table"
require "puma/enhanced/stats/cli/severity_sorter"
require "puma/enhanced/stats/cli/top_renderer"
require "puma/enhanced/stats/cli/summary_renderer"
require "puma/enhanced/stats/cli/frame_renderer"
require "puma/enhanced/stats/cli/runner"
require "puma/enhanced/stats/cli/stub_server"
require "puma/enhanced/stats/cli/user_config"

RSpec.describe "CLI branch gaps" do
  after do
    Puma::Enhanced::Stats::CLI::CgroupMemory.reset!
    Puma::Enhanced::Stats::CLI::Terminal.tty_override = nil
    Puma::Enhanced::Stats::CLI::Terminal.alternate_active = false
  end

  it "covers the remaining uncovered branches" do
    colors = Puma::Enhanced::Stats::CLI::Colors.new(
      Puma::Enhanced::Stats::CLI::Options.new.tap { |o| o.no_color = true }
    )
    expect(Puma::Enhanced::Stats::CLI::MetricLine.new(
      label: "x", value: "1", bar: "#", suffix: "stale 1", colors: colors
    ).render.join).to include "stale 1"

    Puma::Enhanced::Stats::CLI::CgroupMemory.reset!
    stub_const "RUBY_PLATFORM", "linux"
    allow(File).to receive(:read).and_call_original
    allow(File).to receive(:file?).and_call_original
    allow(File).to receive(:file?).with("/sys/fs/cgroup/memory.max").and_return false
    allow(File).to receive(:file?).with("/sys/fs/cgroup/memory/memory.limit_in_bytes").and_return false
    allow(File).to receive(:readlines).with("/proc/meminfo").and_return(["MemTotal:       2048 kB\n"])
    expect(Puma::Enhanced::Stats::CLI::CgroupMemory.total_bytes).to eq 2048 * 1024

    Puma::Enhanced::Stats::CLI::CgroupMemory.reset!
    allow(File).to receive(:file?).with("/sys/fs/cgroup/memory.max").and_return false
    allow(File).to receive(:file?).with("/sys/fs/cgroup/memory/memory.limit_in_bytes").and_return true
    allow(File).to receive(:read).with("/sys/fs/cgroup/memory/memory.limit_in_bytes").and_return "4096\n"
    allow(File).to receive(:file?).with("/sys/fs/cgroup/memory.current").and_return false
    allow(File).to receive(:file?).with("/sys/fs/cgroup/memory/memory.usage_in_bytes").and_return false
    expect(Puma::Enhanced::Stats::CLI::CgroupMemory.total_bytes).to eq 4096
    expect(Puma::Enhanced::Stats::CLI::CgroupMemory.used_bytes).to be_nil

    ra = Puma::Enhanced::Stats::CLI::ResourceAttribution
    bare = Puma::Enhanced::Stats::CLI::HostMetrics::Snapshot.new(
      load: nil, cpu: nil, memory: nil, swap: nil, memory_limit_hint: nil
    )
    expect(ra.send :top_mem_suffix, bare, :ok, 0, 0).to be_nil
    expect(ra.send :top_mem_suffix, bare, :warn, 0, 0).to be_nil
    expect(ra.send :host_hot?, bare).to be false

    item = { "id" => "1", "started_at" => "t", "path_info" => "/x", "method" => "GET", "session" => {} }
    table = Puma::Enhanced::Stats::CLI::RequestTable.new([item], inner_width: 40, display_mode: "stack", offset: 0)
    allow(table).to receive(:stack_fields).and_return %w[path_info method]
    expect(table.send(:stack_item_lines, item).join "\n").to include "METHOD"

    workers = [{
      "index" => 0, "pid" => 1, "synced_at" => "2026-01-01T00:00:00Z",
      "puma" => { "backlog" => 0 },
      "requests" => { "items" => [{ "id" => "1" }], "meta" => { "request_limit" => 2 } }
    }]
    expect(Puma::Enhanced::Stats::CLI::SeveritySorter.sort_workers(
      workers, process_by_pid: {}, interval: 5, mode: "cluster", collected_at: "2026-01-01T00:00:10Z"
    ).first["index"]).to eq 0

    host = Puma::Enhanced::Stats::CLI::HostMetrics::Snapshot.new(
      load: [0.1, 0.2, 0.3],
      cpu: nil,
      memory: Puma::Enhanced::Stats::CLI::HostMetrics::Usage.new(used: 1, total: 2, ratio: 0.5),
      swap: nil,
      memory_limit_hint: nil
    )
    options = Puma::Enhanced::Stats::CLI::Options.new.tap { |o| o.no_color = true }
    bar = Puma::Enhanced::Stats::CLI::Bar.new colors
    attribution = ra.compute(host: host, puma_pids: [], process_by_pid: {})
    top = Puma::Enhanced::Stats::CLI::TopRenderer.new(options, bar, host: host, attribution: attribution)
    budget = Puma::Enhanced::Stats::CLI::LayoutBudget.new(30, 80, options, worker_count: 1)
    expect(top.render_top budget).to include "Load"

    summary = Puma::Enhanced::Stats::CLI::SummaryRenderer.new bar, colors
    payload = mixed_payload.merge(
      "summary" => mixed_payload["summary"].merge(
        "workers_reporting" => 3, "workers_total" => 3, "workers_stale" => 0,
        "requests_in_flight" => 0
      ),
      "workers" => []
    )
    expect(summary.render(payload, budget, attribution: attribution)).to include "SUMMARY"

    compact_payload = {
      "meta" => mixed_payload["meta"],
      "summary" => mixed_payload["summary"],
      "workers" => [{
        "index" => 0, "pid" => 1, "synced_at" => mixed_payload["meta"]["collected_at"],
        "puma" => { "running" => 1, "max_threads" => 5, "backlog" => 0, "pool_capacity" => 4, "busy_threads" => 1 },
        "requests" => {
          "items" => [{ "id" => "1", "started_at" => "2026-01-01T00:00:00Z", "path_info" => "/short", "session" => {} }],
          "meta" => { "request_limit" => 10, "count" => 1, "limit_policy" => "drop", "truncated" => false, "dropped_count" => 0 }
        }
      }]
    }
    options.frame_layout = "compact"
    frame_budget = Puma::Enhanced::Stats::CLI::LayoutBudget.new(40, 80, options, worker_count: 1, layout: "compact")
    frame = Puma::Enhanced::Stats::CLI::FrameRenderer.new options, frame_budget, bar, colors
    sections = frame.send(
      :worker_sections, compact_payload, {}, Puma::Enhanced::Stats::CLI::ScrollState.new, 5, "compact"
    )
    expect(sections.first).to include "WORKER 0"

    allow(Puma::Enhanced::Stats::CLI::UserConfig).to receive(:load).and_return "frame_layout" => "grid"
    cli_runner = Puma::Enhanced::Stats::CLI::Runner.new
    cli_runner.send :parse, ["--no-watch"]
    expect(Puma::Enhanced::Stats::CLI::UserConfig).to have_received :load

    options = Puma::Enhanced::Stats::CLI::Options.new
    options.no_top = true
    cli_runner.instance_variable_set :@options, options
    cli_runner.instance_variable_set(:@fetcher, instance_double(Puma::Enhanced::Stats::CLI::Fetcher, fetch: mixed_payload, master_pid: nil))
    cli_runner.instance_variable_set(:@scroll, Puma::Enhanced::Stats::CLI::ScrollState.new)
    cli_runner.instance_variable_set(:@screen, Puma::Enhanced::Stats::CLI::ScreenManager.new(options))
    allow(Puma::Enhanced::Stats::CLI::Terminal).to receive(:tty?).and_return false
    allow(Puma::Enhanced::Stats::CLI::Terminal).to receive(:resize_pending).and_return false
    allow(Puma::Enhanced::Stats::CLI::ProcessSampler).to receive(:sample_all).and_return({})
    allow(cli_runner).to receive(:monotonic).and_return 1000, 1000, 1006, 1006
    allow(cli_runner).to receive :print_frame
    allow(cli_runner).to receive(:loop).and_yield
    allow(Puma::Enhanced::Stats::CLI::Keyboard).to receive(:refresh?).and_return false
    expect(Puma::Enhanced::Stats::CLI::HostMetrics).not_to receive :read
    expect(cli_runner.send :run_watch, mixed_payload).to eq 0

    allow(Puma::Enhanced::Stats::CLI::Terminal).to receive(:resize_pending).and_return true, false
    expect(cli_runner.send :run_watch, mixed_payload).to eq 0

    server = Puma::Enhanced::Stats::CLI::StubServer.new port: 0, token: nil, payload: { "ok" => true }
    socket = instance_double(TCPSocket, close: nil)
    allow(socket).to receive(:gets).and_return "GET /enhanced-stats HTTP/1.1\r\n", "\r\n"
    allow(socket).to receive(:write) { |body| expect(body).to include "200 OK" }
    server.send :handle, socket
  end
end
