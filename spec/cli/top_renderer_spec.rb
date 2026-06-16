# frozen_string_literal: true

require "puma/enhanced/stats/cli/top_renderer"
require "puma/enhanced/stats/cli/colors"
require "puma/enhanced/stats/cli/bar"
require "puma/enhanced/stats/cli/options"
require "puma/enhanced/stats/cli/layout_budget"
require "puma/enhanced/stats/cli/host_metrics"

RSpec.describe Puma::Enhanced::Stats::CLI::TopRenderer do
  let(:payload) { JSON.parse(File.read("spec/fixtures/enhanced-stats-v1.sample.json")) }
  let(:options) { Puma::Enhanced::Stats::CLI::Options.new.tap { |o| o.no_color = true } }
  let(:colors) { Puma::Enhanced::Stats::CLI::Colors.new(options) }
  let(:bar) { Puma::Enhanced::Stats::CLI::Bar.new(colors) }
  let(:budget) { Puma::Enhanced::Stats::CLI::LayoutBudget.new(40, 100, options, worker_count: 1) }
  let(:host_snapshot) do
    Puma::Enhanced::Stats::CLI::HostMetrics::Snapshot.new(
      load: [0.12, 0.08, 0.05],
      cpu: Puma::Enhanced::Stats::CLI::HostMetrics::CPU.new(usr: 10.0, sys: 5.0, idle: 85.0, usage: 0.15),
      memory: Puma::Enhanced::Stats::CLI::HostMetrics::Usage.new(used: 512_000_000, total: 1_073_741_824, ratio: 0.48),
      swap: Puma::Enhanced::Stats::CLI::HostMetrics::Usage.new(used: 0, total: 0, ratio: 0.0)
    )
  end

  before do
    allow(Puma::Enhanced::Stats::CLI::HostMetrics).to receive(:read).and_return(host_snapshot)
  end

  it "renders deterministic SYSTEM and PROCESSES blocks" do
    renderer = described_class.new(options, colors, bar, master_pid: 1234)
    system = renderer.render_system(budget)
    processes = renderer.render_processes(payload, budget, refresh_interval: 5)

    expect(system).to include("SYSTEM")
    expect(system).to include("Load")
    expect(system).to include("CPU")
    expect(processes).to include("PROCESSES")
    expect(processes).to include("PID")
    expect(processes).to include("1234")
  end

  it "renders swap usage and unavailable host metrics" do
    swap_snapshot = Puma::Enhanced::Stats::CLI::HostMetrics::Snapshot.new(
      load: host_snapshot.load,
      cpu: host_snapshot.cpu,
      memory: host_snapshot.memory,
      swap: Puma::Enhanced::Stats::CLI::HostMetrics::Usage.new(used: 128_000_000, total: 256_000_000, ratio: 0.5)
    )
    allow(Puma::Enhanced::Stats::CLI::HostMetrics).to receive(:read).and_return(swap_snapshot)
    renderer = described_class.new(options, colors, bar, master_pid: nil)
    system = renderer.render_system(budget)

    expect(system).to include("Swap")

    allow(Puma::Enhanced::Stats::CLI::HostMetrics).to receive(:read).and_return(
      Puma::Enhanced::Stats::CLI::HostMetrics::EMPTY
    )
    empty_renderer = described_class.new(options, colors, bar, master_pid: nil)
    system = empty_renderer.render_system(budget)

    expect(system).to include("Host metrics unavailable")
  end

  it "sorts process rows and enriches them from ps output" do
    sort_options = Puma::Enhanced::Stats::CLI::Options.new.tap { |o| o.no_color = true; o.sort = "rss" }
    renderer = described_class.new(sort_options, colors, bar, master_pid: 1234)
    allow(renderer).to receive(:`).with(/ps -o/).and_return("12345  10.0  1.2  1000\n9999  5.0  0.5  500\n")

    output = renderer.render_processes(payload, budget, refresh_interval: 5)

    expect(output).to include("sorted by rss")
    expect(output).to include("12345")
  end

  it "sorts process rows by cpu and backlog" do
    cpu_renderer = described_class.new(
      Puma::Enhanced::Stats::CLI::Options.new.tap { |o| o.no_color = true; o.sort = "cpu" },
      colors,
      bar,
      master_pid: nil
    )
    backlog_renderer = described_class.new(
      Puma::Enhanced::Stats::CLI::Options.new.tap { |o| o.no_color = true; o.sort = "backlog" },
      colors,
      bar,
      master_pid: nil
    )

    expect(cpu_renderer.render_processes(payload, budget, refresh_interval: 5)).to include("sorted by cpu")
    expect(backlog_renderer.render_processes(payload, budget, refresh_interval: 5)).to include("sorted by backlog")
  end

  it "ignores ps failures when enriching process rows" do
    renderer = described_class.new(options, colors, bar, master_pid: 1234)
    allow(renderer).to receive(:`).with(/ps -o/).and_raise(StandardError)

    expect(renderer.render_processes(payload, budget, refresh_interval: 5)).to include("1234")
  end

  it "renders partial system metrics and workers without rss" do
    partial_snapshot = Puma::Enhanced::Stats::CLI::HostMetrics::Snapshot.new(
      load: [0.12, 0.08, 0.05],
      cpu: nil,
      memory: nil,
      swap: nil
    )
    allow(Puma::Enhanced::Stats::CLI::HostMetrics).to receive(:read).and_return(partial_snapshot)
    renderer = described_class.new(options, colors, bar, master_pid: nil)
    system = renderer.render_system(budget)

    expect(system).to include("Load")
    expect(system).not_to include("CPU")
    expect(system).not_to include("Memory")
    expect(system).not_to include("Swap")

    rssless = payload.merge(
      "workers" => [payload["workers"].first.merge("process" => { "cpu_percent" => 1.0 })]
    )
    output = renderer.render_processes(rssless, budget, refresh_interval: 5)

    expect(output).to include("  -")
  end
end
