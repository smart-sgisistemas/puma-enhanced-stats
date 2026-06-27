# frozen_string_literal: true

require "puma/enhanced/stats/cli/format"

RSpec.describe Puma::Enhanced::Stats::CLI::Format do
  it "truncates long strings" do
    expect(described_class.truncate "abcdef", 4).to eq "abc…"
  end

  it "formats bytes" do
    expect(described_class.bytes 2_684_354_560).to eq "2.5 GiB"
  end

  it "formats elapsed milliseconds" do
    expect(described_class.elapsed_ms 1500).to eq "1.5s"
    expect(described_class.elapsed_ms 120_000).to eq "2.0m"
    expect(described_class.elapsed_ms nil).to eq "n/a"
  end

  it "formats smaller byte sizes" do
    expect(described_class.bytes 512).to eq "512 B"
    expect(described_class.bytes 2048).to eq "2 KiB"
    expect(described_class.bytes 2_097_152).to eq "2 MiB"
    expect(described_class.bytes nil).to eq "n/a"
  end

  it "formats relative timestamps" do
    now = Time.utc 2026, 6, 12, 12, 0, 0
    expect(described_class.rel_time nil, now: now).to eq "never"
    expect(described_class.rel_time "2026-06-12T11:59:30Z", now: now).to eq "30s ago"
    expect(described_class.rel_time "2026-06-12T11:00:00Z", now: now).to eq "60m ago"
    expect(described_class.rel_time "not-a-date", now: now).to eq "n/a"
  end

  it "falls back when hostname lookup fails" do
    allow(Socket).to receive(:gethostname).and_raise StandardError

    expect(described_class.hostname).to eq "localhost"
  end

  it "formats elapsed durations and collected clock fallbacks" do
    expect(described_class.elapsed "2026-01-01T02:00:00Z", "2026-01-01T00:00:00Z").to include "h"
    expect(described_class.elapsed "2026-01-01T00:00:00Z", "").to eq "n/a"
    expect(described_class.collected_clock "not-a-date").to eq "not-a-date"
    expect(described_class.collected_clock nil).to eq "n/a"
  end

  it "formats column labels" do
    expect(described_class.cols_label(1)).to eq "1 COL"
    expect(described_class.cols_label(80)).to eq "80 COLS"
  end

  it "wraps segment groups without splitting fixed fields" do
    lines = described_class.wrap_segments(
      %w[cluster sync\ 5s collected\ 14:32:01 80\ COLS],
      separator: " │ ",
      width: 30
    )

    expect(lines.join).to include("80 COLS")
    expect(lines).to include(a_string_matching(/cluster/))
    expect(lines.none? { |line| line.start_with?("COLS") }).to be true
  end

  it "centers visible text in a slot" do
    expect(described_class.center_display("OK", 10)).to eq "    OK    "
    expect(described_class.center_display("CRIT", 10)).to eq "   CRIT   "
  end

  it "wraps plain text across lines" do
    lines = described_class.wrap("Terminal too narrow: need at least 80 columns.", 20)

    expect(lines.size).to be > 1
    expect(lines.join).to include("Terminal too narrow")
    expect(lines.join).to include("80 columns")
  end

  it "wraps indented request fields across lines" do
    lines = described_class.wrap_indented(
      "  └ path_info: ",
      "/api/v2/organizations/acme-corp/reports/quarterly/2026/Q1/export/detailed",
      40
    )

    expect(lines.size).to be > 1
    expect(lines[1]).to start_with(" " * described_class.display_length("  └ path_info: "))
  end

  it "builds table rows and truncates aggressively" do
    expect(described_class.truncate "ab", 1).to eq ""
    expect(described_class.table_row %w[a bb], [3, 4]).to eq "a    bb  "
    expect(described_class.column_widths [%w[ab c], %w[a longer]]).to eq [2, 6]
  end

  it "truncates and pads ANSI-colored text by visible width" do
    red = "\e[31m#{'█' * 30}\e[0m"
    expect(described_class.display_length(red)).to eq 30
    expect(described_class.pad_right(red, 10)).to end_with "\e[0m"
    expect(described_class.display_length(described_class.pad_right(red, 10))).to eq 10
  end
end
