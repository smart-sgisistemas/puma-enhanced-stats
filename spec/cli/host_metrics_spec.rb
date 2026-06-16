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
      "SwapTotal:       2048000 kB\n",
      "SwapFree:        1024000 kB\n"
    ])

    described_class.reset_cpu_sample!
    snapshot = described_class.read

    expect(snapshot.load).to eq([0.10, 0.20, 0.30])
    expect(snapshot.memory.total).to eq(1024000 * 1024)
    expect(snapshot.cpu.usr).to eq(0)
    expect(snapshot.swap.total).to eq(2048000 * 1024)
  end

  it "computes cpu deltas on a second sample" do
    skip "linux-only" unless RUBY_PLATFORM.match?(/linux/i)

    allow(File).to receive(:read).with("/proc/loadavg").and_return("0.10 0.20 0.30 1/100 12345\n")
    allow(File).to receive(:readlines).with("/proc/meminfo").and_return([
      "MemTotal:       1024000 kB\n",
      "MemAvailable:    512000 kB\n",
      "SwapTotal:             0 kB\n",
      "SwapFree:              0 kB\n"
    ])
    allow(File).to receive(:readlines).with("/proc/stat").and_return(["cpu  100 20 30 800 0 0 0 0 0 0\n"])
    described_class.reset_cpu_sample!
    described_class.read
    allow(File).to receive(:readlines).with("/proc/stat").and_return(["cpu  200 40 60 1600 0 0 0 0 0 0\n"])

    snapshot = described_class.read

    expect(snapshot.cpu.usr).to be > 0
    expect(snapshot.cpu.usage).to be > 0
  end

  it "reads darwin metrics when sysctl and vm_stat are available" do
    stub_const("RUBY_PLATFORM", "arm64-darwin23")
    allow(described_class).to receive(:`).and_return(
      "{ 0.10 0.20 0.30 }\n",
      "100 20 30 800\n",
      "4096\n",
      "8589934592\n",
      <<~VMSTAT
        Pages active: 1000.
        Pages wired down: 500.
      VMSTAT
    )

    described_class.reset_cpu_sample!
    snapshot = described_class.read

    expect(snapshot.load).to eq([0.10, 0.20, 0.30])
    expect(snapshot.memory.total).to eq(8589934592)
    expect(snapshot.swap.ratio).to eq(0.0)
  end

  it "returns empty snapshot when host metrics fail" do
    stub_const("RUBY_PLATFORM", "linux")
    allow(described_class).to receive(:read_load).and_raise(RuntimeError, "boom")

    expect(described_class.read).to eq(described_class::EMPTY)
  end

  it "returns nil load when sysctl output is unavailable" do
    stub_const("RUBY_PLATFORM", "arm64-darwin23")
    allow(described_class).to receive(:`) do |cmd|
      case cmd
      when "sysctl -n vm.loadavg" then raise StandardError, "boom"
      when "sysctl -n kern.cp_time" then "100 20 30 800\n"
      when "sysctl -n hw.pagesize" then "4096\n"
      when "sysctl -n hw.memsize" then "8589934592\n"
      when "vm_stat" then <<~VMSTAT
        Pages active: 1000.
        Pages wired down: 500.
      VMSTAT
      else
        raise StandardError, "unexpected: #{cmd}"
      end
    end

    snapshot = described_class.read

    expect(snapshot.load).to be_nil
    expect(snapshot.memory.total).to eq(8589934592)
  end

  it "returns zero cpu usage when totals do not advance" do
    skip "linux-only" unless RUBY_PLATFORM.match?(/linux/i)

    allow(File).to receive(:read).with("/proc/loadavg").and_return("0.10 0.20 0.30 1/100 12345\n")
    allow(File).to receive(:readlines).with("/proc/meminfo").and_return([
      "MemTotal:       1024000 kB\n",
      "MemAvailable:    512000 kB\n",
      "SwapTotal:             0 kB\n",
      "SwapFree:              0 kB\n"
    ])
    allow(File).to receive(:readlines).with("/proc/stat").and_return(["cpu  100 20 30 800 0 0 0 0 0 0\n"])
    described_class.reset_cpu_sample!
    described_class.read
    allow(File).to receive(:readlines).with("/proc/stat").and_return(["cpu  100 20 30 800 0 0 0 0 0 0\n"])

    snapshot = described_class.read

    expect(snapshot.cpu.usr).to be_nil
    expect(snapshot.cpu.usage).to be_nil
  end

  it "returns empty cpu metrics when /proc/stat has no aggregate line" do
    skip "linux-only" unless RUBY_PLATFORM.match?(/linux/i)

    allow(File).to receive(:read).with("/proc/loadavg").and_return("0.10 0.20 0.30 1/100 12345\n")
    allow(File).to receive(:readlines).with("/proc/stat").and_return(["cpu0  100 20 30 800 0 0 0 0 0 0\n"])
    allow(File).to receive(:readlines).with("/proc/meminfo").and_return([
      "MemTotal:             0 kB\n",
      "MemAvailable:         0 kB\n",
      "SwapTotal:             0 kB\n",
      "SwapFree:              0 kB\n"
    ])

    snapshot = described_class.read

    expect(snapshot.cpu.usr).to be_nil
    expect(snapshot.memory.ratio).to eq(0.0)
  end

  it "ignores malformed meminfo lines on linux" do
    skip "linux-only" unless RUBY_PLATFORM.match?(/linux/i)

    allow(File).to receive(:read).with("/proc/loadavg").and_return("0.10 0.20 0.30 1/100 12345\n")
    allow(File).to receive(:readlines).with("/proc/stat").and_return(["cpu  100 20 30 800 0 0 0 0 0 0\n"])
    allow(File).to receive(:readlines).with("/proc/meminfo").and_return([
      "MemTotal:\n",
      "MemAvailable:    512000 kB\n",
      "SwapTotal:\n",
      "SwapFree:        1024000 kB\n",
      "InvalidLine\n"
    ])

    snapshot = described_class.read

    expect(snapshot.memory.total).to eq(0)
    expect(snapshot.swap.total).to eq(0)
  end

  it "reads darwin memory and swap fallbacks" do
    stub_const("RUBY_PLATFORM", "arm64-darwin23")
    allow(described_class).to receive(:`).and_return(
      "{ 0.10 0.20 0.30 }\n",
      "100 20 30 800\n",
      "4096\n",
      "0\n",
      <<~VMSTAT
        Malformed page line
        Pages wired down: 500.
      VMSTAT
    )

    described_class.reset_cpu_sample!
    snapshot = described_class.read

    expect(snapshot.memory.total).to eq(0)
    expect(snapshot.memory.ratio).to eq(0.0)
    expect(snapshot.swap.total).to eq(0)
  end
end
