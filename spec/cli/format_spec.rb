# frozen_string_literal: true

require "puma/enhanced/stats/cli/format"

RSpec.describe Puma::Enhanced::Stats::CLI::Format do
  it "truncates long strings" do
    expect(described_class.truncate("abcdef", 4)).to eq("abc…")
  end

  it "formats bytes" do
    expect(described_class.bytes(2_684_354_560)).to eq("2.5 GiB")
  end

  it "formats elapsed milliseconds" do
    expect(described_class.elapsed_ms(1500)).to eq("1.5s")
  end
end
