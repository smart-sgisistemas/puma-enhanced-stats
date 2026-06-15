# frozen_string_literal: true

require "puma/enhanced/stats/cli/layout_budget"
require "puma/enhanced/stats/cli/options"

RSpec.describe Puma::Enhanced::Stats::CLI::LayoutBudget do
  let(:options) { Puma::Enhanced::Stats::CLI::Options.new }

  it "falls back from compact mode with too many workers" do
    options.compact = true
    budget = described_class.new(40, 140, options, worker_count: 3)

    expect(budget.compact_grid).to be(false)
    expect(budget.warnings.join).to include("at most 2 workers")
  end

  it "enables compact grid for two workers on wide terminals" do
    options.compact = true
    budget = described_class.new(40, 140, options, worker_count: 2)

    expect(budget.compact_grid).to be(true)
  end
end
