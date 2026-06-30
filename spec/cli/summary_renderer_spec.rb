# frozen_string_literal: true

require "puma/enhanced/stats/cli/summary_renderer"

RSpec.describe Puma::Enhanced::Stats::CLI::SummaryRenderer do
  let(:options) { Puma::Enhanced::Stats::CLI::Options.new.tap { |o| o.no_color = true } }
  let(:colors) { Puma::Enhanced::Stats::CLI::Colors.new options }
  let(:bar) { Puma::Enhanced::Stats::CLI::Bar.new colors }
  let(:renderer) { described_class.new bar, colors }
  let(:budget) { Puma::Enhanced::Stats::CLI::LayoutBudget.new(30, 80, options, worker_count: 0) }
  let(:attribution) do
    Puma::Enhanced::Stats::CLI::ResourceAttribution.compute(
      host: Puma::Enhanced::Stats::CLI::HostMetrics::EMPTY,
      puma_pids: [], process_by_pid: {}, degraded: false
    )
  end

  it "marks all workers reporting as ok when counts match and sync is fresh" do
    payload = {
      "collected_at" => "2026-06-12T14:32:01Z",
      "workers_total" => 3,
      "workers_reporting" => 3,
      "workers_stale" => 0,
      "requests_in_flight" => 0,
      "backlog_total" => 0,
      "busy_threads_total" => 0,
      "max_threads_total" => 15,
      "pool_capacity_total" => 15,
      "worker_status" => [
        { "index" => 0, "last_enhanced_checkin" => "2026-06-12T14:31:59Z" },
        { "index" => 1, "last_enhanced_checkin" => "2026-06-12T14:31:58Z" },
        { "index" => 2, "last_enhanced_checkin" => "2026-06-12T14:31:57Z" }
      ],
      "_cli" => { "worker_check_interval_seconds" => 5 }
    }

    output = renderer.render(payload, budget, attribution: attribution)

    expect(output).to match(/Workers reporting\s+3 \/ 3/)
    expect(output).to include "OK"
    expect(output).not_to include "WARN"
    expect(output).not_to include "CRIT"
  end

  it "marks workers reporting as warn when sync is stale within 2x interval" do
    payload = {
      "collected_at" => "2026-06-12T14:32:01Z",
      "workers_total" => 3,
      "workers_reporting" => 3,
      "workers_stale" => 0,
      "requests_in_flight" => 0,
      "backlog_total" => 0,
      "busy_threads_total" => 0,
      "max_threads_total" => 15,
      "pool_capacity_total" => 15,
      "worker_status" => [
        { "index" => 0, "last_enhanced_checkin" => "2026-06-12T14:31:59Z" },
        { "index" => 1, "last_enhanced_checkin" => "2026-06-12T14:31:58Z" },
        { "index" => 2, "last_enhanced_checkin" => "2026-06-12T14:31:53Z" }
      ],
      "_cli" => { "worker_check_interval_seconds" => 5 }
    }

    output = renderer.render(payload, budget, attribution: attribution)

    expect(output).to include "stale 1"
  end

  it "uses zero ratio when max threads is zero" do
    payload = {
      "collected_at" => "2026-06-12T14:32:01Z",
      "backlog" => 0,
      "running" => 0,
      "pool_capacity" => 0,
      "busy_threads" => 0,
      "max_threads" => 0,
      "requests_in_flight" => 0,
      "requests" => []
    }

    output = renderer.render(payload, budget, attribution: attribution)

    expect(output).to match(/Requests in flight\s+0 \/ 0/)
    expect(output).not_to include "Workers reporting"
    expect(output).to include "Running"
  end
end
