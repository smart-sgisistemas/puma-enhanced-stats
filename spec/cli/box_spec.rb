# frozen_string_literal: true

require "puma/enhanced/stats/cli/box"

RSpec.describe Puma::Enhanced::Stats::CLI::Box do
  it "draws double headers and optional badges" do
    simple = described_class.new(40).draw(title: "SUMMARY", lines: ["line"])
    double = described_class.new(40).draw(title: "HEADER", lines: ["line"], style: :double, badge: "WARN")
    divided = described_class.new(40).draw_with_divider(
      title: "WORKER 0",
      top_lines: ["metric"],
      bottom_lines: ["request"],
      badge: "CRIT"
    )

    expect(simple).to include("┌─ SUMMARY")
    expect(double).to include("╔─ HEADER ─ WARN")
    expect(divided).to include("WORKER 0 ─ CRIT")
  end

  it "keeps a minimum border width for long titles" do
    output = described_class.new(12).draw(title: "VERY LONG TITLE", lines: ["x"])

    expect(output).to include("┌─")
    expect(output.lines.size).to be >= 3
  end
end
