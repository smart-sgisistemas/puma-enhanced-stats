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
end
