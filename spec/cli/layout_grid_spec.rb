# frozen_string_literal: true

require "puma/enhanced/stats/cli/layout_grid"
require "puma/enhanced/stats/cli/format"

RSpec.describe Puma::Enhanced::Stats::CLI::LayoutGrid do
  it "requires at least 80 columns and caps layout at 100" do
    expect(described_class.too_narrow?(79)).to be true
    expect(described_class.too_narrow?(80)).to be false
    expect(described_class.cap_cols(120)).to eq 100
    expect(described_class.cap_cols(80)).to eq 80
  end

  it "right-aligns bars with a fixed centered badge slot" do
    colors = Puma::Enhanced::Stats::CLI::Colors.new(
      Puma::Enhanced::Stats::CLI::Options.new.tap { |o| o.no_color = true }
    )
    bar = "##########----------"
    row = described_class.metric_row(
      label: "Backlog total", value: "3 / 15", bar: bar, suffix: :crit,
      colors: colors, content_width: 77
    ).last
    bar_w = described_class.bar_width_for(77)

    expect(Puma::Enhanced::Stats::CLI::Format.display_length(row)).to eq 77
    expect(row).to include("[#{bar}#{' ' * (bar_w - bar.length)}]")
    expect(row).to end_with("   CRIT   ")
    expect(bar_w).to eq 32
  end

  it "reserves badge space on label rows without a bar" do
    colors = Puma::Enhanced::Stats::CLI::Colors.new(
      Puma::Enhanced::Stats::CLI::Options.new.tap { |o| o.no_color = true }
    )
    metric = described_class.metric_row(
      label: "synced_at", value: "8s ago", bar: "--------------------", suffix: :warn,
      colors: colors, content_width: 77
    ).last
    label = described_class.label_row(
      label: "synced_at", value: "8s ago", badge: :warn,
      colors: colors, content_width: 77
    ).last

    expect(Puma::Enhanced::Stats::CLI::Format.display_length(label)).to eq 77
    expect(label[-10..]).to eq metric[-10..]
  end

  it "wraps long values instead of truncating fixed slots" do
    rows = described_class.metric_rows(
      label: "Memory", value: "1024 MiB / 2048 MiB", bar: "####", suffix: :ok,
      colors: nil, content_width: 77
    )

    expect(rows.size).to be > 1
    expect(rows.join).to include("1024 MiB")
    expect(rows.join.gsub(/\s+/, "")).to include("2048MiB")
  end

  it "renders cpu detail and usage on separate lines" do
    bar = "##########----------"
    rows = described_class.cpu_breakdown_rows(
      label: "CPU",
      usr: 49.1, sys: 4.2, idle: 46.7,
      bar: bar,
      suffix: " 51%",
      content_width: 77
    )
    bar_w = described_class.bar_width_for(
      77, value_width: described_class::HOST_VALUE_WIDTH, label_width: described_class::TOP_LABEL_WIDTH
    )

    expect(rows.size).to eq 2
    expect(rows.first).to include "user 49.1%"
    expect(rows.first).to include "sys  4.2%"
    expect(rows.first).to include "idle 46.7%"
    expect(rows.last).to include("[#{bar}#{' ' * (bar_w - bar.length)}]")
  end
end
