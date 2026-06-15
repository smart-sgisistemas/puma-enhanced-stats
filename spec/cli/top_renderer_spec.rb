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
end
