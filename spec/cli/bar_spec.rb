# frozen_string_literal: true

require "puma/enhanced/stats/cli/bar"
require "puma/enhanced/stats/cli/colors"

RSpec.describe Puma::Enhanced::Stats::CLI::Bar do
  let(:options) { Puma::Enhanced::Stats::CLI::Options.new.tap { |o| o.no_color = true } }
  let(:colors) { Puma::Enhanced::Stats::CLI::Colors.new(options) }
  let(:bar) { described_class.new(colors) }

  it "renders filled and empty segments" do
    rendered, label = bar.render(0.5, width: 10, backlog: false)
    expect(rendered).to include("█").and include("░")
    expect(label).to eq(" 50%")
  end

  it "marks backlog queues" do
    _rendered, label = bar.render(0.2, width: 10, backlog: true)
    expect(label).to eq("queue")
  end

  it "clamps ratios outside the 0..1 range" do
    _rendered, low = bar.render(-0.5, width: 10, backlog: false)
    _rendered, high = bar.render(1.5, width: 10, backlog: false)

    expect(low).to eq("ok")
    expect(high).to eq("saturated")
  end
end

RSpec.describe Puma::Enhanced::Stats::CLI::Colors do
  it "paints text when colors are enabled" do
    options = Puma::Enhanced::Stats::CLI::Options.new
    allow(Puma::Enhanced::Stats::CLI::Terminal).to receive(:tty?).and_return(true)
    colors = described_class.new(options)

    expect(colors.paint("ok")).to include("ok")
    expect(colors.level(0.75)).to eq(:warn)
  end
end
