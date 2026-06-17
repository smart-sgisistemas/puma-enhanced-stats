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
    expect(described_class.elapsed_ms(120_000)).to eq("2.0m")
    expect(described_class.elapsed_ms(nil)).to eq("n/a")
  end

  it "formats smaller byte sizes" do
    expect(described_class.bytes(512)).to eq("512 B")
    expect(described_class.bytes(2048)).to eq("2 KiB")
    expect(described_class.bytes(2_097_152)).to eq("2 MiB")
    expect(described_class.bytes(nil)).to eq("n/a")
  end

  it "formats relative timestamps" do
    now = Time.utc(2026, 6, 12, 12, 0, 0)
    expect(described_class.rel_time(nil, now: now)).to eq("never")
    expect(described_class.rel_time("2026-06-12T11:59:30Z", now: now)).to eq("30s ago")
    expect(described_class.rel_time("2026-06-12T11:00:00Z", now: now)).to eq("60m ago")
    expect(described_class.rel_time("not-a-date", now: now)).to eq("n/a")
  end

  it "falls back when hostname lookup fails" do
    allow(Socket).to receive(:gethostname).and_raise(StandardError)

    expect(described_class.hostname).to eq("localhost")
  end

  it "builds table rows and truncates aggressively" do
    expect(described_class.truncate("ab", 1)).to eq("")
    expect(described_class.table_row(%w[a bb], [3, 4])).to eq("a    bb  ")
    expect(described_class.column_widths([%w[ab c], %w[a longer]])).to eq([2, 6])
  end
end
