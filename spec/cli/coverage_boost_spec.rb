# frozen_string_literal: true

require "json"
require "puma/enhanced/stats/cli/runner"
require "puma/enhanced/stats/cli/stub_server"
require "puma/enhanced/stats/cli/top_renderer"
require "puma/enhanced/stats/cli/screen_manager"
require "puma/enhanced/stats/cli/frame_renderer"
require "puma/enhanced/stats/cli/resource_attribution"
require "puma/enhanced/stats/cli/alert_level"
require "puma/enhanced/stats/cli/format"
require "puma/enhanced/stats/cli/user_config"
require "puma/enhanced/stats/cli/stub_payload_builder"
require "puma/enhanced/stats/cli/request_sorter"
require "puma/enhanced/stats/cli/request_filter"
require "puma/enhanced/stats/cli/terminal"
require "puma/enhanced/stats/cli/sync_freshness"

RSpec.describe "CLI coverage boost" do
  it "covers alert levels and format edge cases" do
    expect(Puma::Enhanced::Stats::CLI::AlertLevel.for_truncated true).to eq :info
    expect(Puma::Enhanced::Stats::CLI::AlertLevel.for_backlog 1).to eq :crit
    expect(Puma::Enhanced::Stats::CLI::Format.elapsed("2026-01-01T00:01:00Z", "2026-01-01T00:00:00Z")).to include "m"
    expect(Puma::Enhanced::Stats::CLI::Format.elapsed("bad", "2026-01-01T00:00:00Z")).to eq "n/a"
    expect(Puma::Enhanced::Stats::CLI::RequestSorter.sort([{ "x" => 1 }], field: "x", dir: "asc")).to eq [{ "x" => 1 }]
  end

  it "covers user config save and stub scenarios" do
    path = File.join(Dir.tmpdir, "pesrc-#{Process.pid}")
    options = Puma::Enhanced::Stats::CLI::Options.new
    options.frame_layout = "grid"
    Puma::Enhanced::Stats::CLI::UserConfig.save! options, path
    expect(Puma::Enhanced::Stats::CLI::UserConfig.load(path)["frame_layout"]).to eq "grid"
    File.delete path
    expect(Puma::Enhanced::Stats::CLI::StubPayloadBuilder.build(scenario: "stale", workers: 1, stale: 0)).to be_a Hash
    expect(Puma::Enhanced::Stats::CLI::StubScenarios::NAMES).to include "mixed"
  end

  it "covers terminal alternate screen helpers" do
    allow(Puma::Enhanced::Stats::CLI::Terminal).to receive(:tty?).and_return true
    Puma::Enhanced::Stats::CLI::Terminal.enter_alternate_screen!
    Puma::Enhanced::Stats::CLI::Terminal.leave_alternate_screen!
    Puma::Enhanced::Stats::CLI::Terminal.clear
  end

  it "covers sync freshness warn path and request filter session fields" do
    result = Puma::Enhanced::Stats::CLI::SyncFreshness.evaluate(
      synced_at: "2026-01-01T00:00:00Z",
      collected_at: "2026-01-01T00:00:08Z",
      interval_seconds: 5,
      mode: "cluster"
    )
    expect(result.badge).to eq :warn
    items = [{ "session" => { "uid" => "1" } }]
    filtered = Puma::Enhanced::Stats::CLI::RequestFilter.apply(items, { "session.uid" => "1" })
    expect(filtered.size).to eq 1
  end

  it "covers top renderer sort keys and empty host" do
    options = Puma::Enhanced::Stats::CLI::Options.new
    options.sort_process = "cpu"
    colors = Puma::Enhanced::Stats::CLI::Colors.new(options.tap { |o| o.no_color = true })
    bar = Puma::Enhanced::Stats::CLI::Bar.new colors
    host = Puma::Enhanced::Stats::CLI::HostMetrics::EMPTY
    attribution = Puma::Enhanced::Stats::CLI::ResourceAttribution.compute(
      host: host, puma_pids: [], process_by_pid: {}, degraded: true
    )
    renderer = Puma::Enhanced::Stats::CLI::TopRenderer.new(
      options, bar, host: host, attribution: attribution, process_by_pid: {}
    )
    budget = Puma::Enhanced::Stats::CLI::LayoutBudget.new(24, 80, options, worker_count: 1)
    payload = { "workers" => [{ "index" => 0, "pid" => 1, "puma" => { "running" => 1, "max_threads" => 5, "backlog" => 0, "pool_capacity" => 4 } }] }
    %w[rss backlog index].each { |sort| options.sort_process = sort; renderer.render_processes(payload, budget, refresh_interval: 1) }
    expect(renderer.render_top budget).to include "unavailable"
  end

  it "covers stub server auth and not found" do
    server = Puma::Enhanced::Stats::CLI::StubServer.new port: 0, token: "secret", payload: {}
    socket = instance_double(TCPSocket, close: nil)
    allow(socket).to receive(:gets).and_return "GET /missing HTTP/1.1\r\n", "\r\n"
    allow(socket).to receive :write
    server.send :handle, socket
    socket2 = instance_double(TCPSocket, close: nil)
    allow(socket2).to receive(:gets).and_return "GET /enhanced-stats HTTP/1.1\r\n", "\r\n"
    allow(socket2).to receive :write
    server.send :handle, socket2
  end

  it "covers screen manager unknown keys and runner modal frame" do
    options = Puma::Enhanced::Stats::CLI::Options.new
    scroll = Puma::Enhanced::Stats::CLI::ScrollState.new
    manager = Puma::Enhanced::Stats::CLI::ScreenManager.new(options)
    payload = { "workers" => [{ "index" => 0, "requests" => { "items" => [] } }] }
    expect(manager.handle("z", scroll: scroll, payload: payload)).to be false
    options.modal = :sort
    expect(manager.render_modal(Puma::Enhanced::Stats::CLI::LayoutBudget.new(24, 80, options, worker_count: 1))).to include "SORT"
  end

  it "covers frame renderer grid and outsiders panel" do
    output = render_dashboard(width: 120, frame_layout: "grid", no_top: true)
    expect(output).to include "WORKER"
    options = Puma::Enhanced::Stats::CLI::Options.new
    options.show_outsiders = true
    attribution = Puma::Enhanced::Stats::CLI::ResourceAttribution.compute(
      host: Puma::Enhanced::Stats::CLI::HostMetrics::EMPTY,
      puma_pids: [1], process_by_pid: {
        1 => Puma::Enhanced::Stats::CLI::ProcessSampler::Sample.new(pid: 1, cpu_percent: 1, mem_percent: 1, rss_bytes: 1)
      }, degraded: false
    )
    allow(attribution).to receive(:outsiders).and_return([
      Puma::Enhanced::Stats::CLI::ProcessSampler::Outsider.new(
        pid: 9, cpu_percent: 1, mem_percent: 1, rss_bytes: 1024, command: "sidekiq"
      )
    ])
    budget = Puma::Enhanced::Stats::CLI::LayoutBudget.new(40, 120, options, worker_count: 2, layout: "stacked")
    expect(Puma::Enhanced::Stats::CLI::OutsidersRenderer.new.render attribution, budget).to include "OUTSIDE PUMA"
  end
end

RSpec.describe Puma::Enhanced::Stats::CLI::Runner do
  it "renders modal frame when a modal is open" do
    fetcher = instance_double(Puma::Enhanced::Stats::CLI::Fetcher, fetch: mixed_payload, master_pid: nil)
    allow(Puma::Enhanced::Stats::CLI::Fetcher).to receive(:new).and_return fetcher
    allow(Puma::Enhanced::Stats::CLI::UserConfig).to receive(:load).and_return({})
    allow(Puma::Enhanced::Stats::CLI::ProcessSampler).to receive(:sample_all).and_return({})
    allow(Puma::Enhanced::Stats::CLI::HostMetrics).to receive(:read).and_return(Puma::Enhanced::Stats::CLI::HostMetrics::EMPTY)
    allow(Puma::Enhanced::Stats::CLI::Terminal).to receive(:size).and_return [40, 80]
    runner = described_class.new
    runner.instance_variable_set(:@options, Puma::Enhanced::Stats::CLI::Options.new.tap { |o| o.no_watch = true; o.modal = :help })
    runner.instance_variable_set :@fetcher, fetcher
    runner.instance_variable_set(:@scroll, Puma::Enhanced::Stats::CLI::ScrollState.new)
    runner.instance_variable_set(:@screen, Puma::Enhanced::Stats::CLI::ScreenManager.new(runner.instance_variable_get :@options))
    expect(runner.send :render_frame, mixed_payload).to include "HELP"
  end
end
