# frozen_string_literal: true

RSpec.describe Puma::Enhanced::Stats::Snapshot do
  let(:launcher) do
    stats = {
      worker_status: [
        {
          index: 0,
          pid: 123,
          last_status: { backlog: 0, running: 1, pool_capacity: 5, max_threads: 5, requests_count: 1 },
          enhanced_stats: {
            items: [{ "id" => "a", "started_at" => (Time.now.utc - 2).iso8601, "method" => "GET", "path_info" => "/" }],
            process: { rss_bytes: 100, cpu_percent: 1.0 },
            dropped_count: 0,
            truncated: false,
            synced_at: Time.now.utc.iso8601
          }
        }
      ]
    }

    instance_double(
      "Launcher",
      config: instance_double("Config", options: { enhanced_stats: Puma::Enhanced::Stats::Configuration.new }),
      stats_hash: stats
    )
  end

  it "builds public contract" do
    payload = described_class.build(launcher)

    expect(payload["schema_version"]).to eq(1)
    expect(payload["meta"]["mode"]).to eq("cluster")
    expect(payload["summary"]["requests_in_flight"]).to eq(1)
    expect(payload["workers"].first["requests"]["meta"]["request_limit"]).to eq(100)
    expect(payload["workers"].first["requests"]["items"].first["elapsed_ms"]).to be_a(Integer)
  end

  it "reads enhanced stats from cluster workers" do
    worker = double(
      "WorkerHandle",
      index: 0,
      enhanced_stats: {
        items: [{ "id" => "a", "started_at" => (Time.now.utc - 2).iso8601, "method" => "GET", "path_info" => "/" }],
        process: { rss_bytes: 100, cpu_percent: 1.0 },
        dropped_count: 0,
        truncated: false,
        synced_at: Time.now.utc.iso8601
      }
    )
    config = Puma::Configuration.new do |user|
      user.workers 2
    end
    launcher = Puma::Launcher.new(config)
    allow(launcher).to receive(:stats).and_return(
      worker_status: [
        { index: 0, pid: 123, last_status: { backlog: 0, running: 1, pool_capacity: 5, max_threads: 5, requests_count: 1 } }
      ]
    )
    allow(launcher).to receive(:workers).and_return([worker])

    payload = described_class.build(launcher)

    expect(payload["workers"].first["process"]["rss_bytes"]).to eq(100)
    expect(payload["workers"].first["requests"]["items"].size).to eq(1)
  end

  it "leaves synced_at null for cluster workers without enhanced stats" do
    launcher = instance_double(
      "Launcher",
      config: instance_double("Config", options: { enhanced_stats: Puma::Enhanced::Stats::Configuration.new }),
      stats_hash: {
        worker_status: [
          {
            index: 0,
            pid: 123,
            last_status: { backlog: 0, running: 0, pool_capacity: 5, max_threads: 5, requests_count: 0 }
          }
        ]
      }
    )

    payload = described_class.build(launcher)

    expect(payload["workers"].first["synced_at"]).to be_nil
    expect(payload["summary"]["workers_reporting"]).to eq(0)
  end

  it "builds single mode when the launcher exposes no stats methods" do
    config = instance_double("Config", options: { enhanced_stats: Puma::Enhanced::Stats::Configuration.new })
    launcher = double("Launcher", config: config)
    allow(launcher).to receive(:respond_to?).with(:stats).and_return(false)
    allow(launcher).to receive(:respond_to?).with(:stats_hash).and_return(false)

    payload = described_class.build(launcher)

    expect(payload["meta"]["mode"]).to eq("single")
    expect(payload["workers"].first["puma"]).to eq(
      "backlog" => 0,
      "running" => 0,
      "pool_capacity" => 0,
      "max_threads" => 0,
      "requests_count" => 0
    )
  end

  it "ignores workers on non-Puma launchers in cluster mode" do
    launcher = instance_double(
      "Launcher",
      config: instance_double("Config", options: { enhanced_stats: Puma::Enhanced::Stats::Configuration.new }),
      stats_hash: {
        worker_status: [
          {
            index: 0,
            pid: 123,
            last_status: { backlog: 0, running: 0, pool_capacity: 5, max_threads: 5, requests_count: 0 }
          }
        ]
      }
    )

    payload = described_class.build(launcher)

    expect(payload["workers"].first["synced_at"]).to be_nil
    expect(payload["workers"].first["requests"]["items"]).to be_empty
  end

  context "single mode" do
    let(:launcher) do
      instance_double(
        "Launcher",
        config: instance_double("Config", options: { enhanced_stats: Puma::Enhanced::Stats::Configuration.new }),
        stats_hash: {
          backlog: 0,
          running: 1,
          pool_capacity: 5,
          max_threads: 5,
          requests_count: 3,
          last_status: { backlog: 0, running: 1, pool_capacity: 5, max_threads: 5, requests_count: 3 }
        }
      )
    end

    before do
      registry = Puma::Enhanced::Stats::CurrentRequests.instance
      registry.reset!
      registry.register(
        "REQUEST_METHOD" => "GET",
        "PATH_INFO" => "/slow",
        "QUERY_STRING" => "",
        "REMOTE_ADDR" => "127.0.0.1"
      )
    end

    it "reads live registry and process metrics" do
      payload = described_class.build(launcher)

      expect(payload["meta"]["mode"]).to eq("single")
      expect(payload["workers"].size).to eq(1)
      expect(payload["workers"].first["requests"]["items"].first["path_info"]).to end_with("/slow")
      expect(payload["workers"].first["process"]).to include("rss_bytes", "cpu_percent")
    end
  end

  describe ".item_with_elapsed" do
    let(:now) { Time.utc(2026, 6, 12, 10, 0, 2) }

    it "calculates elapsed_ms from started_at" do
      item = { "id" => "a", "started_at" => "2026-06-12T10:00:00Z", "method" => "GET" }
      result = described_class.send(:item_with_elapsed, item, now)

      expect(result["elapsed_ms"]).to eq(2000)
    end

    it "calculates elapsed_ms even when a custom elapsed_ms field is registered" do
      item = { "id" => "a", "started_at" => "2026-06-12T10:00:00Z", "elapsed_ms" => 999 }
      result = described_class.send(:item_with_elapsed, item, now)

      expect(result["elapsed_ms"]).to eq(2000)
    end

    it "returns nil elapsed_ms for invalid started_at" do
      item = { "id" => "a", "started_at" => "not-a-time" }
      result = described_class.send(:item_with_elapsed, item, now)

      expect(result["elapsed_ms"]).to be_nil
    end
  end

  describe ".pick_puma_stats" do
    it "normalizes symbol and string keys" do
      stats = described_class.send(
        :pick_puma_stats,
        backlog: 1,
        "running" => 2,
        pool_capacity: 3,
        max_threads: 4,
        requests_count: 5
      )

      expect(stats).to eq(
        "backlog" => 1,
        "running" => 2,
        "pool_capacity" => 3,
        "max_threads" => 4,
        "requests_count" => 5
      )
    end
  end

  describe ".normalize_process" do
    it "normalizes symbol and string keys" do
      expect(described_class.send(:normalize_process, rss_bytes: 100, cpu_percent: 1.5)).to eq(
        "rss_bytes" => 100,
        "cpu_percent" => 1.5
      )
    end

    it "returns EMPTY when raw is nil" do
      expect(described_class.send(:normalize_process, nil)).to eq(Puma::Enhanced::Stats::ProcessMetrics::EMPTY)
    end
  end

  describe ".requests_section" do
    let(:config) { Puma::Enhanced::Stats::Configuration.new }

    it "builds requests meta and items" do
      section = described_class.send(
        :requests_section,
        items: [{ "id" => "a" }],
        config: config,
        truncated: true,
        dropped_count: 2
      )

      expect(section["meta"]).to eq(
        "count" => 1,
        "request_limit" => 100,
        "limit_policy" => "keep_longest",
        "truncated" => true,
        "dropped_count" => 2
      )
      expect(section["items"]).to eq([{ "id" => "a" }])
    end
  end

  describe ".summary" do
    it "aggregates worker metrics" do
      workers = [
        {
          "synced_at" => "2026-06-12T10:00:00Z",
          "requests" => { "meta" => { "count" => 2, "dropped_count" => 1 } }
        },
        {
          "synced_at" => nil,
          "requests" => { "meta" => { "count" => 1, "dropped_count" => 0 } }
        }
      ]

      summary = described_class.send(:summary, workers)

      expect(summary).to eq(
        "workers_total" => 2,
        "workers_reporting" => 1,
        "requests_in_flight" => 3,
        "requests_dropped_total" => 1
      )
    end
  end
end
