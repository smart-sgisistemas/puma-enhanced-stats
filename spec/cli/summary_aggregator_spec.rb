# frozen_string_literal: true

require "puma/enhanced/stats/cli/summary_aggregator"

RSpec.describe Puma::Enhanced::Stats::CLI::SummaryAggregator do
  let(:payload) do
    JSON.parse(File.read("spec/fixtures/enhanced-stats-v1.sample.json"))
  end

  it "aggregates backlog and thread totals" do
    lines = described_class.new(payload).lines
    backlog = lines.find { |line| line.label == "Backlog (global)" }
    threads = lines.find { |line| line.label == "Threads in use" }

    expect(backlog.value).to eq("0")
    expect(threads.value).to eq("1 / 5")
  end

  it "flags global backlog warnings" do
    payload["workers"] << {
      "index" => 1,
      "pid" => 99,
      "synced_at" => Time.now.utc.iso8601,
      "puma" => { "backlog" => 3, "running" => 5, "pool_capacity" => 0, "max_threads" => 5, "requests_count" => 0 },
      "process" => { "rss_bytes" => 1000, "cpu_percent" => 10.0 },
      "requests" => { "meta" => { "count" => 0, "request_limit" => 100, "limit_policy" => "keep_longest", "truncated" => false, "dropped_count" => 0 }, "items" => [] }
    }
    payload["summary"]["workers_total"] = 2
    payload["summary"]["workers_reporting"] = 2

    backlog = described_class.new(payload).lines.find { |line| line.label == "Backlog (global)" }
    expect(backlog.level).to eq(:warn)
    expect(backlog.value).to eq("3")
  end

  it "flags critical backlog, thread, and pool saturation" do
    payload["workers"] = [{
      "index" => 0,
      "pid" => 1,
      "puma" => { "backlog" => 5, "running" => 5, "pool_capacity" => 0, "max_threads" => 5 },
      "process" => {}
    }]

    lines = described_class.new(payload).lines
    backlog = lines.find { |line| line.label == "Backlog (global)" }
    threads = lines.find { |line| line.label == "Threads in use" }
    pool = lines.find { |line| line.label == "Pool capacity free" }

    expect(backlog.level).to eq(:crit)
    expect(threads.level).to eq(:crit)
    expect(pool.level).to eq(:crit)
  end

  it "flags warning levels for elevated utilization" do
    payload["workers"] = [{
      "index" => 0,
      "pid" => 1,
      "puma" => { "backlog" => 1, "running" => 4, "pool_capacity" => 1, "max_threads" => 5 },
      "process" => {}
    }]

    lines = described_class.new(payload).lines
    threads = lines.find { |line| line.label == "Threads in use" }
    pool = lines.find { |line| line.label == "Pool capacity free" }

    expect(threads.level).to eq(:warn)
    expect(pool.level).to eq(:warn)
  end

  it "warns when only some workers are reporting" do
    payload["summary"]["workers_total"] = 2
    payload["summary"]["workers_reporting"] = 1

    reporting = described_class.new(payload).lines.find { |line| line.label == "Workers reporting" }

    expect(reporting.level).to eq(:warn)
  end
end
