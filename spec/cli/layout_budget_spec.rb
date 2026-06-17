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
    expect(budget.worker_inner_width).to eq(140)
  end

  it "enables compact grid for two workers on wide terminals" do
    options.compact = true
    budget = described_class.new(40, 140, options, worker_count: 2)

    expect(budget.compact_grid).to be(true)
    expect(budget.worker_inner_width).to eq(68)
  end

  it "warns when compact mode needs a wider terminal" do
    options.compact = true
    budget = described_class.new(40, 100, options, worker_count: 2)

    expect(budget.compact_grid).to be(false)
    expect(budget.warnings.join).to include("width >= 120")
  end

  it "reserves space for top and watch sections" do
    budget = described_class.new(40, 100, options, worker_count: 1)

    expect(budget.available_for_workers).to eq(15)
  end

  it "reserves less space when watch is disabled" do
    options.no_watch = true
    budget = described_class.new(40, 100, options, worker_count: 1)

    expect(budget.available_for_workers).to eq(18)
  end

  it "reserves less space when top is hidden" do
    options.no_top = true
    budget = described_class.new(40, 100, options, worker_count: 1)

    expect(budget.available_for_workers).to eq(27)
  end
end
