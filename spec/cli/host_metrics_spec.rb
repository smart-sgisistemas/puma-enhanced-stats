# frozen_string_literal: true

require "puma/enhanced/stats/cli/host_metrics"

RSpec.describe Puma::Enhanced::Stats::CLI::HostMetrics do
  after do
    described_class.previous_cpu = nil
  end

  it "returns empty snapshot on unsupported platforms" do
    stub_const("RUBY_PLATFORM", "java")

    expect(described_class.read).to eq(described_class::EMPTY)
  end

  it "reads linux load and memory from /proc" do
    skip "linux-only" unless RUBY_PLATFORM.match?(/linux/i)

    allow(File).to receive(:read).with("/proc/loadavg").and_return("0.10 0.20 0.30 1/100 12345\n")
    allow(File).to receive(:readlines).with("/proc/stat").and_return(["cpu  100 20 30 800 0 0 0 0 0 0\n"])
    allow(File).to receive(:readlines).with("/proc/meminfo").and_return([
      "MemTotal:       1024000 kB\n",
      "MemAvailable:    512000 kB\n",
      "SwapTotal:             0 kB\n",
      "SwapFree:              0 kB\n"
    ])

    described_class.reset_cpu_sample!
    snapshot = described_class.read

    expect(snapshot.load).to eq([0.10, 0.20, 0.30])
    expect(snapshot.memory.total).to eq(1024000 * 1024)
    expect(snapshot.cpu.usr).to eq(0)
  end
end
