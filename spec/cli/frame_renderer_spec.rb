# frozen_string_literal: true

require "puma/enhanced/stats/cli/metric_line"
require "puma/enhanced/stats/cli/label_line"

module FrameRendererSpecHelpers
  module_function

  def summary_content_lines(output)
    lines = output.lines
    start = lines.index { |l| l.include? "SUMMARY" }
    return [] unless start

    lines[(start + 1)..].take_while { |l| !l.start_with? "└" }.select { |l| l.start_with? "│ " }
  end
end

RSpec.configure do |config|
  config.include FrameRendererSpecHelpers
end

RSpec.describe "CLI grid alignment" do
  it "right-aligns metric bars within the content width" do
    colors = Puma::Enhanced::Stats::CLI::Colors.new(
      Puma::Enhanced::Stats::CLI::Options.new.tap { |o| o.no_color = true }
    )
    bar = Puma::Enhanced::Stats::CLI::Bar.new colors
    line = Puma::Enhanced::Stats::CLI::MetricLine.new(
      label: "backlog", value: "3 / 5", suffix: :crit,
      colors: colors, ratio: 0.6, bar_renderer: bar, backlog: true
    ).render(content_width: 77).last

    expect(Puma::Enhanced::Stats::CLI::Format.display_length(line)).to eq 77
    expect(line).to end_with("   CRIT   ")
    expect(line).to include "["
  end

  it "renders LabelLine without a bar region" do
    line = Puma::Enhanced::Stats::CLI::LabelLine.new(
      label: "Requests truncated", value: "yes", badge: :info
    ).render.last

    expect(line).not_to include "["
    expect(line).to include("info").or include "INFO"
  end
end

RSpec.describe "UI acceptance criteria" do
  it "renders SUMMARY with exactly 7 lines in mixed scenario" do
    output = render_dashboard(width: 80, no_top: true)
    expect(summary_content_lines(output).size).to eq 7
  end

  it "uses info badge for requests_truncated" do
    output = render_dashboard(width: 80, no_top: true)
    expect(output).to match /Requests truncated\s+yes.*info/i
  end

  it "does not stack method at width 200 inline" do
    output = render_dashboard(width: 200, request_display: "inline", no_top: true)
    expect(output).not_to include("└ method:")
  end

  it "stacks path_info at width 80" do
    output = render_dashboard(width: 80, request_display: "stack", no_top: true)
    expect(output).to include("└ path_info:")
  end

  it "wraps long path_info across lines in stack mode" do
    output = render_dashboard(width: 80, request_display: "stack", no_top: true)
    expect(output).to include("└ path_info:")
    expect(output).to include("└ METHOD:")
  end

  it "shows a display error below 80 columns" do
    output = render_dashboard(width: 79, no_top: true)
    expect(output).to include("DISPLAY ERROR")
    expect(output).to include("at least 80 columns")
    expect(output).to include("pass -w 80")
  end

  it "shows terminal width in the header" do
    output = render_dashboard(width: 80, no_top: true)
    expect(output).to include("80 COLS")
    expect(output).to include("cluster")
    expect(output).to include("collected")
  end

  it "wraps the full display error message on very narrow terminals" do
    output = render_dashboard(width: 40, no_top: true)
    expect(output).to include("DISPLAY ERROR")
    expect(output).to include("Terminal too narrow")
    expect(output).to include("Resize the window")
    expect(output).to include("pass -w 80")
    expect(output.lines.count { |line| line.start_with?("│ ") }).to be > 1
  end

  it "keeps dashboard boxes within 100 columns on wide terminals" do
    output = render_dashboard(width: 200, no_top: true)
    border_lines = output.lines.map(&:chomp).select { |line| line.start_with?("┌", "└") }
    expect(border_lines).not_to be_empty
    expect(border_lines.map(&:length).max).to be <= 100
  end

  it "separates sections with blank lines" do
    output = render_dashboard(width: 80, no_top: true)
    expect(output.scan("\n\n\n").size).to be >= 2
  end
end

RSpec.describe Puma::Enhanced::Stats::CLI::ScrollState do
  it "keeps offset across clamp when count is stable" do
    scroll = described_class.new
    scroll.bump_request! 0, 3
    payload = { "workers" => [{ "index" => 0, "requests" => { "items" => Array.new(10) { {} } } }] }
    scroll.clamp! payload
    expect(scroll.request_offset_for 0).to eq 3
  end
end
