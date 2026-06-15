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
      registry = Puma::Enhanced::Stats::CurrentRequestsRegistry.instance
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
end
