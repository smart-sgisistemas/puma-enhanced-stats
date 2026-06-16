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

  it "filters and sorts workers" do
    workers_payload = payload.merge(
      "workers" => [
        payload["workers"].first,
        payload["workers"].first.merge("index" => 1, "pid" => 99, "process" => { "cpu_percent" => 50.0, "rss_bytes" => 999 })
      ]
    )
    filter_options = Puma::Enhanced::Stats::CLI::Options.new.tap { |o| o.no_color = true; o.worker = 1 }
    filter_renderer = described_class.new(filter_options, colors, bar)
    body = filter_renderer.render_body(workers_payload, budget)

    expect(body).to include("WORKER 1")
    expect(body).not_to include("WORKER 0 ─")

    sort_options = Puma::Enhanced::Stats::CLI::Options.new.tap { |o| o.no_color = true; o.sort = "cpu" }
    sort_renderer = described_class.new(sort_options, colors, bar)
    sorted = sort_renderer.render_body(workers_payload, budget)

    expect(sorted.index("WORKER 1")).to be < sorted.index("WORKER 0")

    rss_options = Puma::Enhanced::Stats::CLI::Options.new.tap { |o| o.no_color = true; o.sort = "rss" }
    expect(described_class.new(rss_options, colors, bar).render_body(workers_payload, budget)).to include("WORKER")

    backlog_options = Puma::Enhanced::Stats::CLI::Options.new.tap { |o| o.no_color = true; o.sort = "backlog" }
    expect(described_class.new(backlog_options, colors, bar).render_body(workers_payload, budget)).to include("WORKER")
  end

  it "renders a compact worker grid and watch footer" do
    compact_options = Puma::Enhanced::Stats::CLI::Options.new.tap do |o|
      o.no_color = true
      o.compact = true
      o.watch = true
    end
    compact_budget = Puma::Enhanced::Stats::CLI::LayoutBudget.new(40, 140, compact_options, worker_count: 2)
    compact_payload = payload.merge(
      "workers" => [
        payload["workers"].first,
        payload["workers"].first.merge("index" => 1, "pid" => 99)
      ]
    )
    compact_renderer = described_class.new(compact_options, colors, bar)
    body = compact_renderer.render_body(compact_payload, compact_budget, refresh_interval: 5)

    expect(body).to include("WORKERS")
    expect(body).to include("FOOTER")
    expect(body).to include("Refresh 5s")
  end

  it "formats invalid collected timestamps as plain text" do
    invalid_payload = payload.merge("meta" => payload["meta"].merge("collected_at" => "not-a-time"))
    header = renderer.render_header(invalid_payload, budget)

    expect(header).to include("Collected not-a-time")
  end

  it "renders worker badges, truncated requests, and warning summary rows" do
    workers_payload = {
      "summary" => {
        "workers_total" => 1,
        "workers_reporting" => 0,
        "requests_in_flight" => 0,
        "requests_dropped_total" => 1
      },
      "workers" => [
        payload["workers"].first.merge(
          "synced_at" => nil,
          "process" => {},
          "requests" => payload["workers"].first["requests"].merge("meta" => payload["workers"].first["requests"]["meta"].merge("truncated" => true))
        ),
        payload["workers"].first.merge(
          "index" => 1,
          "pid" => 99,
          "puma" => payload["workers"].first["puma"].merge("running" => 5, "backlog" => 2)
        )
      ]
    }
    body = renderer.render_body(workers_payload, budget)

    expect(body).to include("[CRIT] not synced")
    expect(body).to include("[trunc]")
    expect(body).to include("[WARN]")
    expect(body).to include("Dropped total")
  end

  it "skips worker sections when no workers are present" do
    empty_payload = payload.merge("workers" => [])
    body = renderer.render_body(empty_payload, budget)

    expect(body).to include("SUMMARY")
    expect(body).not_to include("WORKER 0")
  end

  it "renders queue badges and zero-thread workers" do
    workers_payload = {
      "summary" => payload["summary"],
      "workers" => [
        payload["workers"].first.merge(
          "puma" => { "backlog" => 2, "running" => 1, "pool_capacity" => 3, "max_threads" => 5 },
          "process" => { "cpu_percent" => 12.5, "rss_bytes" => 256_000_000 }
        ),
        payload["workers"].first.merge(
          "index" => 1,
          "pid" => 99,
          "puma" => { "backlog" => 3, "running" => 0, "pool_capacity" => 0, "max_threads" => 0 },
          "process" => {}
        )
      ]
    }
    body = renderer.render_body(workers_payload, budget)

    expect(body).to include("[WARN] queue")
    expect(body).to include("CPU")
    expect(body).to include("RSS")
    expect(body).to include("Backlog")
    expect(body).to include("WORKER 1")
  end

  it "computes backlog bars when max threads is zero" do
    worker = {
      "index" => 1,
      "pid" => 99,
      "puma" => { "backlog" => 3, "running" => 0, "pool_capacity" => 0, "max_threads" => 0 },
      "process" => {}
    }
    lines = renderer.send(:worker_metric_lines, worker, worker["puma"], worker["process"], 100)

    expect(lines.join("\n")).to include("Backlog")
    expect(lines.join("\n")).to include("3")
  end

  it "computes zero backlog ratio when max threads and backlog are zero" do
    worker = {
      "index" => 1,
      "pid" => 99,
      "puma" => { "backlog" => 0, "running" => 0, "pool_capacity" => 0, "max_threads" => 0 },
      "process" => {}
    }
    lines = renderer.send(:worker_metric_lines, worker, worker["puma"], worker["process"], 100)

    expect(lines.join("\n")).to include("Backlog    0")
  end
end
