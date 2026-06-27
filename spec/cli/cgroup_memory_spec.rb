# frozen_string_literal: true

require "puma/enhanced/stats/cli/cgroup_memory"

RSpec.describe Puma::Enhanced::Stats::CLI::CgroupMemory do
  after do
    described_class.reset!
  end

  it "reads linux memtotal when no cgroup limit is present" do
    stub_const "RUBY_PLATFORM", "linux"
    allow(File).to receive(:file?).and_return false
    allow(File).to receive(:readlines).with("/proc/meminfo").and_return(["MemTotal:       2048000 kB\n"])

    expect(described_class.total_bytes).to eq 2048000 * 1024
    expect(described_class.cgroup_limited?).to be false
    expect(described_class.limit_hint).to be_nil
  end

  it "prefers cgroup v2 memory.max when present" do
    stub_const "RUBY_PLATFORM", "linux"
    allow(File).to receive(:file?).with("/sys/fs/cgroup/memory.max").and_return true
    allow(File).to receive(:file?).and_call_original
    allow(File).to receive(:read).with("/sys/fs/cgroup/memory.max").and_return "536870912\n"
    allow(File).to receive(:read).with("/sys/fs/cgroup/memory.current").and_return "134217728\n"

    expect(described_class.total_bytes).to eq 536_870_912
    expect(described_class.cgroup_limited?).to be true
    expect(described_class.limit_hint).to eq "512 MiB  cgroup"
    expect(described_class.used_bytes).to eq 134_217_728
  end

  it "falls back to cgroup v1 limit when finite" do
    stub_const "RUBY_PLATFORM", "linux"
    allow(File).to receive(:file?).and_call_original
    allow(File).to receive(:file?).with("/sys/fs/cgroup/memory.max").and_return false
    allow(File).to receive(:file?).with("/sys/fs/cgroup/memory/memory.limit_in_bytes").and_return true
    allow(File).to receive(:read).with("/sys/fs/cgroup/memory/memory.limit_in_bytes").and_return "268435456\n"

    expect(described_class.total_bytes).to eq 268_435_456
    expect(described_class.cgroup_limited?).to be true
  end

  it "reads darwin hw.memsize" do
    stub_const "RUBY_PLATFORM", "arm64-darwin23"
    allow(described_class).to receive(:`).with("sysctl -n hw.memsize").and_return "8589934592\n"

    expect(described_class.total_bytes).to eq 8_589_934_592
    expect(described_class.cgroup_limited?).to be false
  end
end
