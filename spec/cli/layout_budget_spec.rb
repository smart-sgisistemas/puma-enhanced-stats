# frozen_string_literal: true

require "puma/enhanced/stats/cli/layout_budget"
require "puma/enhanced/stats/cli/options"

RSpec.describe Puma::Enhanced::Stats::CLI::LayoutBudget do
  let(:options) { Puma::Enhanced::Stats::CLI::Options.new }

  it "uses half width for grid layout workers capped at 100 columns" do
    budget = described_class.new(40, 140, options, worker_count: 2, layout: "grid")
    expect(budget.capped_cols).to eq 100
    expect(budget.worker_inner_width).to eq 48
  end

  it "hides top sections in compact layout" do
    budget = described_class.new(20, 78, options, worker_count: 1, layout: "compact")
    expect(budget.show_top?).to be false
  end

  it "reserves space for top and watch sections" do
    budget = described_class.new(40, 100, options, worker_count: 1)
    expect(budget.available_for_workers).to be >= 8
  end

  it "reserves more space when top is hidden" do
    options.no_top = true
    with_top = described_class.new(40, 100, options, worker_count: 1)
    options.no_top = false
    without_top = described_class.new(40, 100, options, worker_count: 1)
    expect(with_top.available_for_workers).to be > without_top.available_for_workers
  end

  it "chooses stack display mode below inline threshold" do
    budget = described_class.new(40, 79, options, worker_count: 1)
    expect(budget.request_display_mode).to eq "stack"
  end

  it "exposes metric content width from box columns" do
    budget = described_class.new(40, 80, options, worker_count: 1)
    expect(budget.metric_content_width).to eq 77
  end
end
