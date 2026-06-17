# frozen_string_literal: true

RSpec.describe Puma::Enhanced::Stats::Snapshot do
  def default_enhanced_stats(**overrides)
    {
      items: [{ id: "a", started_at: (Time.now.utc - 2).iso8601, method: "GET", path_info: "/" }],
      process: { rss_bytes: 100, cpu_percent: 1.0 },
      dropped_count: 0,
      truncated: false,
      synced_at: Time.now.utc.iso8601
    }.merge(overrides)
  end

  def cluster_launcher(worker_status:, worker_handles: [])
    config = Puma::Configuration.new { |user| user.workers worker_status.size }
    launcher = Puma::Launcher.new(config)
    allow(launcher).to receive(:stats).and_return(worker_status: worker_status)
    allow(launcher).to receive(:workers).and_return(worker_handles)
    launcher
  end

  let(:launcher) do
    cluster_launcher(
      worker_status: [
        {
          index: 0,
          pid: 123,
          last_status: { backlog: 0, running: 1, pool_capacity: 5, max_threads: 5, requests_count: 1 }
        }
      ],
      worker_handles: [
        double(
          "WorkerHandle",
          index: 0,
          enhanced_stats: default_enhanced_stats
        )
      ]
    )
  end

  it "builds public contract from cluster handles" do
    payload = described_class.build(launcher)

    expect(payload[:schema_version]).to eq(described_class::SCHEMA_VERSION)
    expect(payload[:meta][:mode]).to eq("cluster")
    expect(payload[:summary][:requests_in_flight]).to eq(1)
    expect(payload[:workers].first[:process][:rss_bytes]).to eq(100)
    expect(payload[:workers].first[:requests][:meta][:request_limit]).to eq(100)
    expect(payload[:workers].first[:requests][:items].first[:elapsed_ms]).to be_a(Integer)
  end

  it "leaves synced_at null when cluster handles have no enhanced data" do
    launcher = cluster_launcher(
      worker_status: [
        {
          index: 0,
          pid: 123,
          last_status: { backlog: 0, running: 0, pool_capacity: 5, max_threads: 5, requests_count: 0 }
        }
      ],
      worker_handles: []
    )

    payload = described_class.build(launcher)

    expect(payload[:workers].first[:synced_at]).to be_nil
    expect(payload[:workers].first[:process]).to eq(Puma::Enhanced::Stats::ProcessMetrics::EMPTY)
    expect(payload[:summary][:workers_reporting]).to eq(0)
  end

  it "skips handle lookup for non-Puma launchers" do
    launcher = instance_double(
      "Launcher",
      config: instance_double("Config", options: { enhanced_stats: Puma::Enhanced::Stats::Configuration.new, worker_check_interval: 5 }),
      stats: {
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

    expect(payload[:workers].first[:synced_at]).to be_nil
    expect(payload[:workers].first[:requests][:items]).to be_empty
  end

  it "aggregates summary metrics across workers" do
    launcher = cluster_launcher(
      worker_status: [
        {
          index: 0,
          pid: 123,
          last_status: { backlog: 0, running: 1, pool_capacity: 5, max_threads: 5, requests_count: 0 }
        },
        {
          index: 1,
          pid: 124,
          last_status: { backlog: 0, running: 0, pool_capacity: 5, max_threads: 5, requests_count: 0 }
        }
      ],
      worker_handles: [
        double(
          "WorkerHandle",
          index: 0,
          enhanced_stats: default_enhanced_stats(
            items: [{ id: "a", started_at: Time.now.utc.iso8601 }],
            process: { rss_bytes: 1, cpu_percent: 1.0 },
            dropped_count: 1
          )
        ),
        double(
          "WorkerHandle",
          index: 1,
          enhanced_stats: {
            items: [],
            process: nil,
            dropped_count: 0,
            truncated: false,
            synced_at: nil
          }
        )
      ]
    )

    summary = described_class.build(launcher)[:summary]

    expect(summary).to eq(
      workers_total: 2,
      workers_reporting: 1,
      requests_in_flight: 1,
      requests_dropped_total: 1
    )
  end

  it "builds single mode when launcher stats are empty" do
    launcher = instance_double(
      "Launcher",
      config: instance_double("Config", options: { enhanced_stats: Puma::Enhanced::Stats::Configuration.new, worker_check_interval: 5 }),
      stats: {}
    )

    payload = described_class.build(launcher)

    expect(payload[:meta][:mode]).to eq("single")
    expect(payload[:workers].first[:puma]).to eq(
      Puma::Server::STAT_METHODS.to_h { |key| [key, 0] }
    )
  end

  it "reports empty cluster workers" do
    launcher = cluster_launcher(worker_status: [], worker_handles: [])

    payload = described_class.build(launcher)

    expect(payload[:meta][:mode]).to eq("cluster")
    expect(payload[:summary][:workers_total]).to eq(0)
    expect(payload[:workers]).to be_empty
  end

  describe "#workers" do
    it "merges enhanced_stats from handles by index" do
      launcher = cluster_launcher(
        worker_status: [
          { index: 0, pid: 1, last_status: { backlog: 2 } },
          { index: 1, pid: 2, last_status: { backlog: 0 } }
        ],
        worker_handles: [
          double("WorkerHandle", index: 0, enhanced_stats: { items: [{ id: "w0" }], synced_at: "t0" }),
          double("WorkerHandle", index: 1, enhanced_stats: { items: [], synced_at: nil })
        ]
      )
      snapshot = described_class.new(launcher)

      rows = snapshot.send(:workers)

      expect(rows[0][:last_status][:backlog]).to eq(2)
      expect(rows[0][:enhanced_stats][:items].first[:id]).to eq("w0")
      expect(rows[1][:enhanced_stats][:items]).to be_empty
    end

    it "ignores stale enhanced_stats embedded in worker_status" do
      launcher = cluster_launcher(
        worker_status: [
          {
            index: 0,
            pid: 1,
            last_status: { backlog: 0 },
            enhanced_stats: { items: [{ id: "stale" }] }
          }
        ],
        worker_handles: [
          double("WorkerHandle", index: 0, enhanced_stats: { items: [{ id: "live" }], synced_at: "t0" })
        ]
      )

      rows = described_class.new(launcher).send(:workers)

      expect(rows.first[:enhanced_stats][:items].first[:id]).to eq("live")
    end

    it "uses empty enhanced_stats when handle index is missing" do
      launcher = cluster_launcher(
        worker_status: [{ index: 0, pid: 1, last_status: {} }],
        worker_handles: [double("WorkerHandle", index: 1, enhanced_stats: { items: [{ id: "other" }] })]
      )

      rows = described_class.new(launcher).send(:workers)

      expect(rows.first[:enhanced_stats]).to eq(items: [])
    end

    it "falls back to stats when single mode has no last_status" do
      launcher = instance_double(
        "Launcher",
        config: instance_double("Config", options: { enhanced_stats: Puma::Enhanced::Stats::Configuration.new, worker_check_interval: 5 }),
        stats: { backlog: 3, running: 1, pool_capacity: 5, max_threads: 5, requests_count: 1 }
      )
      Puma::Enhanced::Stats::CurrentRequests.reset!

      row = described_class.new(launcher).send(:workers).first

      expect(row[:last_status][:backlog]).to eq(3)
      expect(row[:enhanced_stats][:items]).to be_empty
    end
  end

  context "single mode" do
    let(:launcher) do
      instance_double(
        "Launcher",
        config: instance_double("Config", options: { enhanced_stats: Puma::Enhanced::Stats::Configuration.new, worker_check_interval: 5 }),
        stats: {
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
      Puma::Enhanced::Stats::CurrentRequests.reset!
      Puma::Enhanced::Stats::CurrentRequests.register(
        "REQUEST_METHOD" => "GET",
        "PATH_INFO" => "/slow",
        "QUERY_STRING" => "",
        "REMOTE_ADDR" => "127.0.0.1",
        "action_dispatch.request_id" => "snapshot-slow-request"
      )
    end

    it "reads live registry and process metrics" do
      payload = described_class.build(launcher)

      expect(payload[:meta][:mode]).to eq("single")
      expect(payload[:workers].size).to eq(1)
      expect(payload[:workers].first[:requests][:items].first[:path_info]).to end_with("/slow")
      expect(payload[:workers].first[:process]).to include(:rss_bytes, :cpu_percent)
    end
  end

  describe "#elapsed_request" do
    let(:now) { Time.utc(2026, 6, 12, 10, 0, 2) }
    let(:snapshot) do
      described_class.new(
        instance_double("Launcher", config: instance_double("Config", options: {}), stats: {}),
        now: now
      )
    end

    it "calculates elapsed_ms from started_at" do
      item = { id: "a", started_at: "2026-06-12T10:00:00Z", method: "GET" }
      result = snapshot.send(:elapsed_request, item)

      expect(result[:elapsed_ms]).to eq(2000)
    end

    it "overrides a custom elapsed_ms field with computed value" do
      item = { id: "a", started_at: "2026-06-12T10:00:00Z", elapsed_ms: 999 }
      result = snapshot.send(:elapsed_request, item)

      expect(result[:elapsed_ms]).to eq(2000)
    end

    it "returns nil elapsed_ms for invalid started_at" do
      item = { id: "a", started_at: "not-a-time" }
      result = snapshot.send(:elapsed_request, item)

      expect(result[:elapsed_ms]).to be_nil
    end
  end
end
