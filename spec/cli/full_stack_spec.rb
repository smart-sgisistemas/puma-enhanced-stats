# frozen_string_literal: true

require "puma/enhanced/stats/cli/screen_manager"
require "puma/enhanced/stats/cli/design_screen"
require "puma/enhanced/stats/cli/sort_screen"
require "puma/enhanced/stats/cli/filter_screen"
require "puma/enhanced/stats/cli/help_screen"
require "puma/enhanced/stats/cli/top_renderer"
require "puma/enhanced/stats/cli/frame_renderer"
require "puma/enhanced/stats/cli/request_pipeline"
require "puma/enhanced/stats/cli/request_field_catalog"
require "puma/enhanced/stats/cli/keyboard"
require "puma/enhanced/stats/cli/layout_registry"
require "puma/enhanced/stats/cli/sync_freshness"
require "puma/enhanced/stats/cli/outsiders_renderer"
require "puma/enhanced/stats/cli/stub_server"
require "net/http"

RSpec.describe Puma::Enhanced::Stats::CLI::ScreenManager do
  let(:options) { Puma::Enhanced::Stats::CLI::Options.new }
  let(:scroll) { Puma::Enhanced::Stats::CLI::ScrollState.new }
  let(:payload) { mixed_payload }
  let(:manager) { described_class.new options }

  it "handles dashboard keys and modals" do
    %w[d o f ? h l i t O W x j k [ ] 0].each do |key|
      expect(manager.handle(key, scroll: scroll, payload: payload)).to be true
    end
    options.modal = :help
    expect(manager.handle("n", scroll: scroll, payload: payload)).to be true
    expect(manager.handle("\e", scroll: scroll, payload: payload)).to be true
  end
end

RSpec.describe "CLI modal renderers" do
  let(:options) { Puma::Enhanced::Stats::CLI::Options.new }
  let(:budget) { Puma::Enhanced::Stats::CLI::LayoutBudget.new(24, 80, options, worker_count: 1) }

  it "renders design, sort, filter, and help screens" do
    expect(Puma::Enhanced::Stats::CLI::DesignScreen.new.render options, budget).to include "stacked"
    expect(Puma::Enhanced::Stats::CLI::SortScreen.new.render options, budget).to include "elapsed"
    options.filters["method"] = "GET"
    expect(Puma::Enhanced::Stats::CLI::FilterScreen.new.render options, budget).to include "method=GET"
    expect(Puma::Enhanced::Stats::CLI::HelpScreen.new.render options, budget).to include "HELP"
  end
end

RSpec.describe Puma::Enhanced::Stats::CLI::TopRenderer do
  let(:host) do
    Puma::Enhanced::Stats::CLI::HostMetrics::Snapshot.new(
      load: [0.1, 0.2, 0.3],
      cpu: Puma::Enhanced::Stats::CLI::HostMetrics::CPU.new(usr: 10, sys: 5, idle: 85, usage: 0.15),
      memory: Puma::Enhanced::Stats::CLI::HostMetrics::Usage.new(used: 1_000, total: 2_000, ratio: 0.5),
      swap: Puma::Enhanced::Stats::CLI::HostMetrics::Usage.new(used: 0, total: 1_000, ratio: 0.0),
      memory_limit_hint: "512 MiB  cgroup"
    )
  end

  it "renders TOP and PROCESSES with host and process samples" do
    options = Puma::Enhanced::Stats::CLI::Options.new
    colors = Puma::Enhanced::Stats::CLI::Colors.new(options.tap { |o| o.no_color = true })
    bar = Puma::Enhanced::Stats::CLI::Bar.new colors
    attribution = Puma::Enhanced::Stats::CLI::ResourceAttribution.compute(
      host: host, puma_pids: [48_201], process_by_pid: {
        48_201 => Puma::Enhanced::Stats::CLI::ProcessSampler::Sample.new(
          pid: 48_201, cpu_percent: 10.0, mem_percent: 1.0, rss_bytes: 1024
        )
      }, degraded: false
    )
    renderer = described_class.new(
      options, bar, host: host, attribution: attribution, master_pid: 48_200,
      process_by_pid: {
        48_201 => Puma::Enhanced::Stats::CLI::ProcessSampler::Sample.new(
          pid: 48_201, cpu_percent: 10.0, mem_percent: 1.0, rss_bytes: 1024
        ),
        48_200 => Puma::Enhanced::Stats::CLI::ProcessSampler::Sample.new(
          pid: 48_200, cpu_percent: 1.0, mem_percent: 0.5, rss_bytes: 512
        )
      }
    )
    budget = Puma::Enhanced::Stats::CLI::LayoutBudget.new(40, 80, options, worker_count: 1)
    payload = JSON.parse(File.read(File.expand_path("../fixtures/stub/mixed-cluster.json", __dir__)))
    expect(renderer.render_top budget).to include "TOP"
    expect(renderer.render_processes(payload, budget, refresh_interval: 5)).to include "PROCESSES"
  end
end

RSpec.describe Puma::Enhanced::Stats::CLI::FrameRenderer do
  it "renders split and focus layouts" do
    output = render_dashboard(width: 120, frame_layout: "split", no_top: false)
    expect(output).to include "SUMMARY"
    focus = render_dashboard(width: 80, frame_layout: "focus", no_top: true)
    expect(focus).to include "WORKER"
  end
end

RSpec.describe Puma::Enhanced::Stats::CLI::RequestPipeline do
  it "discovers custom fields and filters items" do
    items = [{ "id" => "1", "started_at" => "2026-01-01T00:00:00Z", "method" => "GET", "session" => { "uid" => "1" } }]
    fields = Puma::Enhanced::Stats::CLI::RequestFieldCatalog.discover items
    expect(fields).to include("session.uid")
    options = Puma::Enhanced::Stats::CLI::Options.new
    options.filters["method"] = "POST"
    expect(Puma::Enhanced::Stats::CLI::RequestPipeline.process(items, collected_at: "2026-01-01T00:01:00Z", options: options)).to be_empty
  end
end

RSpec.describe Puma::Enhanced::Stats::CLI::LayoutRegistry do
  it "falls back when columns are too narrow" do
    options = Puma::Enhanced::Stats::CLI::Options.new
    options.frame_layout = "two_column"
    result = described_class.resolve(options, Puma::Enhanced::Stats::CLI::LayoutBudget.new(24, 80, options, worker_count: 2))
    expect(result.layout).to eq "stacked"
    expect(result.hint).to include "need 120 cols"
  end

  it "forces stacked layout in single mode" do
    options = Puma::Enhanced::Stats::CLI::Options.new
    options.frame_layout = "grid"
    result = described_class.resolve(
      options,
      Puma::Enhanced::Stats::CLI::LayoutBudget.new(40, 200, options, worker_count: 1),
      mode: "single"
    )
    expect(result.layout).to eq "stacked"
    expect(result.hint).to include "single mode"
  end
end

RSpec.describe Puma::Enhanced::Stats::CLI::SyncFreshness do
  it "evaluates stale and never-synced workers" do
    expect(described_class.evaluate(synced_at: nil, collected_at: "2026-01-01T00:00:00Z", interval_seconds: 5, mode: "cluster").badge).to eq :crit
    result = described_class.evaluate(
      synced_at: "2026-01-01T00:00:00Z",
      collected_at: "2026-01-01T00:00:20Z",
      interval_seconds: 5,
      mode: "cluster"
    )
    expect(result.badge).to eq :crit
  end
end

RSpec.describe Puma::Enhanced::Stats::CLI::StubServer do
  it "serves enhanced-stats over HTTP" do
    payload = { "collected_at" => "2026-01-01T00:00:00Z", "worker_status" => [] }
    server = described_class.new port: 0, token: "dev", payload: payload
    thread = Thread.new { server.start }
    20.times do
      break if server.bound_port.positive?

      sleep 0.05
    end
    uri = URI("http://127.0.0.1:#{server.bound_port}/enhanced-stats?token=dev")
    begin
      response = Net::HTTP.get_response uri
    ensure
      thread.kill
    end
    skip "stub server port 9293 unavailable in CI" unless response.is_a?(Net::HTTPSuccess)

    expect(JSON.parse(response.body)["collected_at"]).to eq "2026-01-01T00:00:00Z"
  end
end

RSpec.describe Puma::Enhanced::Stats::CLI::Keyboard do
  it "returns nil when stdin is not a TTY" do
    allow(Puma::Enhanced::Stats::CLI::Terminal).to receive(:tty?).and_return false
    expect(described_class.read(deadline: Time.now.to_i)).to be_nil
    expect(described_class.refresh?).to be false
  end
end

RSpec.describe Puma::Enhanced::Stats::CLI::OutsidersRenderer do
  it "returns nil when outsiders list is empty" do
    attribution = Puma::Enhanced::Stats::CLI::ResourceAttribution.compute(
      host: Puma::Enhanced::Stats::CLI::HostMetrics::EMPTY,
      puma_pids: [], process_by_pid: {}, degraded: false
    )
    budget = Puma::Enhanced::Stats::CLI::LayoutBudget.new(24, 80, Puma::Enhanced::Stats::CLI::Options.new, worker_count: 1)
    expect(described_class.new.render attribution, budget).to be_nil
  end
end
