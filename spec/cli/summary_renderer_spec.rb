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
      "meta" => {
        "collected_at" => "2026-06-12T14:32:01Z",
        "mode" => "cluster",
        "worker_check_interval_seconds" => 5
      },
      "summary" => {
        "workers_reporting" => 3,
        "workers_total" => 3,
        "workers_stale" => 0,
        "requests_in_flight" => 0,
        "requests_dropped_total" => 0,
        "requests_truncated" => false,
        "backlog_total" => 0,
        "busy_threads_total" => 0,
        "max_threads_total" => 15,
        "pool_capacity_total" => 15
      },
      "workers" => [
        { "synced_at" => "2026-06-12T14:31:59Z" },
        { "synced_at" => "2026-06-12T14:31:58Z" },
        { "synced_at" => "2026-06-12T14:31:57Z" }
      ]
    }

    output = renderer.render(payload, budget, attribution: attribution)

    expect(output).to match(/Workers reporting\s+3 \/ 3/)
    expect(output).to include "OK"
    expect(output).not_to include "WARN"
    expect(output).not_to include "CRIT"
  end

  it "marks workers reporting as warn when sync is stale within 2x interval" do
    payload = {
      "meta" => {
        "collected_at" => "2026-06-12T14:32:01Z",
        "mode" => "cluster",
        "worker_check_interval_seconds" => 5
      },
      "summary" => {
        "workers_reporting" => 3,
        "workers_total" => 3,
        "workers_stale" => 0,
        "requests_in_flight" => 0,
        "requests_dropped_total" => 0,
        "requests_truncated" => false,
        "backlog_total" => 0,
        "busy_threads_total" => 0,
        "max_threads_total" => 15,
        "pool_capacity_total" => 15
      },
      "workers" => [
        { "synced_at" => "2026-06-12T14:31:59Z" },
        { "synced_at" => "2026-06-12T14:31:58Z" },
        { "synced_at" => "2026-06-12T14:31:53Z" }
      ]
    }

    output = renderer.render(payload, budget, attribution: attribution)

    expect(output).to include "stale 1"
  end

  it "uses zero ratio when request limits sum to zero" do
    payload = {
      "summary" => {
        "workers_reporting" => 1,
        "workers_total" => 1,
        "workers_stale" => 0,
        "requests_in_flight" => 0,
        "requests_dropped_total" => 0,
        "requests_truncated" => false,
        "backlog_total" => 0,
        "busy_threads_total" => 0,
        "max_threads_total" => 5,
        "pool_capacity_total" => 5
      },
      "workers" => []
    }

    output = renderer.render(payload, budget, attribution: attribution)

    expect(output).to match(/Requests in flight\s+0 \/ 0/)
  end
end
