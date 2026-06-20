# frozen_string_literal: true

RSpec.describe Puma::Enhanced::Stats::ProcessMetrics do
  let(:empty) { described_class::EMPTY }
  let(:instance) { described_class.send(:instance) }
  let(:linux) { RUBY_PLATFORM.match?(/linux/i) }

  before { instance.instance_variable_set(:@last_cpu_sample, nil) }

  it "returns rss and cpu on linux after a warm-up snapshot" do
    skip "process metrics are linux only" unless linux

    described_class.snapshot
    result = described_class.snapshot

    expect(result[:rss_bytes]).to be_a(Integer)
    expect(result[:rss_bytes]).to be_positive
    expect(result[:cpu_percent]).to be_a(Numeric)
  end

  it "returns empty metrics on unsupported platforms" do
    skip "linux loads the full snapshot implementation" if linux

    expect(described_class.snapshot).to eq(empty)
  end

  context "on linux" do
    before { skip "linux only" unless linux }

    it "reads rss from /proc and cpu from delta since the last snapshot" do
      allow(File).to receive(:read).with("/proc/self/status").and_return("VmRSS:\t12345 kB\n")
      allow(Process).to receive(:times).and_return(Struct.new(:utime, :stime).new(7.0, 0.0))
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(1_000.0)

      instance.instance_variable_set(:@last_cpu_sample, { cpu_time_sec: 6.0, at: 999.0 })

      expect(described_class.snapshot).to eq(
        rss_bytes: 12_641_280,
        cpu_percent: 100.0
      )
    end

    it "returns null cpu_percent on the first snapshot" do
      allow(File).to receive(:read).with("/proc/self/status").and_return("VmRSS:\t12345 kB\n")
      allow(Process).to receive(:times).and_return(Struct.new(:utime, :stime).new(7.0, 0.0))

      expect(described_class.snapshot).to eq(
        rss_bytes: 12_641_280,
        cpu_percent: nil
      )
    end

    it "returns empty metrics when VmRSS is missing" do
      allow(File).to receive(:read).with("/proc/self/status").and_return("Name:\truby\n")

      expect(described_class.snapshot).to eq(empty)
    end

    it "returns empty metrics when /proc reads fail" do
      allow(File).to receive(:read).and_raise(Errno::ENOENT)

      expect(described_class.snapshot).to eq(empty)
    end
  end
end
