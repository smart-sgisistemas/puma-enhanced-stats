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
end
