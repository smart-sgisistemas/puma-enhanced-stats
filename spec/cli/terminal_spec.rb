# frozen_string_literal: true

require "puma/enhanced/stats/cli/terminal"

RSpec.describe Puma::Enhanced::Stats::CLI::Terminal do
  after do
    described_class.size_override = nil
    described_class.tty_override = nil
    described_class.reset_resize!
  end

  it "uses size override when set" do
    described_class.size_override = [30, 100]
    expect(described_class.size).to eq([30, 100])
    expect(described_class.cols).to eq(100)
    expect(described_class.rows).to eq(30)
  end

  it "falls back to defaults when not a TTY" do
    described_class.tty_override = false
    expect(described_class.size).to eq([24, 80])
  end

  it "tracks SIGWINCH resize pending flag" do
    described_class.resize_pending = true
    expect(described_class.resize_pending).to be(true)
    described_class.reset_resize!
    expect(described_class.resize_pending).to be(false)
  end
end
