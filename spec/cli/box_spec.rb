# frozen_string_literal: true

require "puma/enhanced/stats/cli/box"

RSpec.describe Puma::Enhanced::Stats::CLI::Box do
  it "draws double headers and optional badges" do
    simple = described_class.new(40).draw(title: "SUMMARY", lines: ["line"])
    double = described_class.new(40).draw title: "HEADER", lines: ["line"], style: :double, badge: "WARN"
    divided = described_class.new(40).draw_with_divider(
      title: "WORKER 0",
      top_lines: ["metric"],
      bottom_lines: ["request"],
      badge: "CRIT"
    )

    expect(simple).to include "┌─ SUMMARY"
    expect(double).to include "╔─ HEADER ─ WARN"
    expect(divided).to include "WORKER 0 ─ CRIT"
  end

  it "keeps a minimum border width for long titles" do
    output = described_class.new(12).draw title: "VERY LONG TITLE", lines: ["x"]

    expect(output).to include "┌─"
    expect(output.lines.size).to be >= 3
  end

  it "unifies width across specs to the widest content" do
    narrow = described_class::Spec.new(title: "A", lines: ["short"])
    wide = described_class::Spec.new(title: "B", lines: ["#{'x' * 40}"])
    width = described_class.unified_width [narrow, wide], 120

    narrow_box = described_class.new(120, fixed_width: width).draw title: narrow.title, lines: narrow.lines
    wide_box = described_class.new(120, fixed_width: width).draw title: wide.title, lines: wide.lines

    expect(narrow_box.lines.first.length).to eq(wide_box.lines.first.length)
  end

  it "keeps every border line at the same display width" do
    long_title = "WORKER 0 ─ pid 48201 ─ synced 2s ago ─ [CRIT] backlog 2"
    red_bar = "\e[31m#{'█' * 20}\e[0m"
    output = described_class.new(60, fixed_width: 60).draw(
      title: long_title,
      lines: ["backlog  2 / 5  [#{red_bar}]  CRIT"],
      border_level: :crit,
      colors: Puma::Enhanced::Stats::CLI::Colors.new(
        Puma::Enhanced::Stats::CLI::Options.new.tap { |o| o.no_color = false }
      )
    )
    widths = output.lines.map { |line| Puma::Enhanced::Stats::CLI::Format.display_length(line.chomp) }

    expect(widths.uniq).to eq [60]
    expect(output).to include "\e[31m"
  end
end
