# frozen_string_literal: true

require "puma/enhanced/stats/cli/request_only_renderer"
require "puma/enhanced/stats/cli/options"
require "puma/enhanced/stats/cli/layout_budget"

RSpec.describe Puma::Enhanced::Stats::CLI::RequestOnlyRenderer do
  let(:payload) { JSON.parse(File.read("spec/fixtures/enhanced-stats-v1.sample.json"), symbolize_names: true) }
  let(:options) { Puma::Enhanced::Stats::CLI::Options.new.tap { |o| o.no_color = true } }
  let(:budget) { Puma::Enhanced::Stats::CLI::LayoutBudget.new(40, 100, options, worker_count: 2) }

  it "renders worker summary and per-worker requests" do
    output = described_class.new(options).render(payload, budget)

    expect(output).to include("WORKERS")
    expect(output).to include("BACKLOG")
    expect(output).to include("WORKER 0")
    expect(output).to include("in-flight")
  end

  it "shows empty state for workers without requests" do
    payload[:workers].each { |worker| worker[:requests] = { :items => [] } }

    output = described_class.new(options).render(payload, budget)

    expect(output).to include("No in-flight requests")
  end

  it "filters to a single worker" do
    payload[:workers] << payload[:workers].first.merge(:index => 1, :pid => 12346)
    options.worker = 1

    output = described_class.new(options).render(payload, budget)

    expect(output).to include("WORKER 1")
    expect(output).not_to match(/WORKER 0 ─/)
  end

  it "renders a footer in watch mode" do
    output = described_class.new(options).render(payload, budget, refresh_interval: 3)

    expect(output).to include("FOOTER")
    expect(output).to include("Refresh 3s")
  end

  it "shows empty worker summary" do
    payload[:workers] = []

    output = described_class.new(options).render(payload, budget)

    expect(output).to include("No workers reporting")
  end

  it "sorts workers by cpu, rss, and backlog" do
    payload[:workers] = [
      payload[:workers].first.merge(:index => 0, :puma => { :backlog => 1 }, :process => { :cpu_percent => 1, :rss_bytes => 100 }),
      payload[:workers].first.merge(:index => 1, :puma => { :backlog => 9 }, :process => { :cpu_percent => 9, :rss_bytes => 900 })
    ]

    %w[cpu rss backlog].each do |key|
      options.sort = key
      output = described_class.new(options).render(payload, budget)
      expect(output.index("1")).to be < output.index("0")
    end
  end
end
