# frozen_string_literal: true

require "puma/enhanced/stats/cli/dashboard_renderer"
require "puma/enhanced/stats/cli/colors"
require "puma/enhanced/stats/cli/bar"
require "puma/enhanced/stats/cli/options"
require "puma/enhanced/stats/cli/layout_budget"

RSpec.describe Puma::Enhanced::Stats::CLI::DashboardRenderer do
  let(:payload) { JSON.parse(File.read("spec/fixtures/enhanced-stats-v1.sample.json")) }
  let(:options) { Puma::Enhanced::Stats::CLI::Options.new.tap { |o| o.no_color = true } }
  let(:colors) { Puma::Enhanced::Stats::CLI::Colors.new(options) }
  let(:bar) { Puma::Enhanced::Stats::CLI::Bar.new(colors) }
  let(:budget) { Puma::Enhanced::Stats::CLI::LayoutBudget.new(40, 100, options, worker_count: 1) }
  let(:renderer) { described_class.new(options, colors, bar) }

  it "renders header and summary sections" do
    header = renderer.render_header(payload, budget)
    body = renderer.render_body(payload, budget)

    expect(header).to include("PUMA ENHANCED STATS")
    expect(body).to include("SUMMARY")
    expect(body).to include("Backlog (global)")
    expect(body).to include("WORKER 0")
  end
end
