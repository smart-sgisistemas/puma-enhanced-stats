# frozen_string_literal: true

require "puma/enhanced/stats"

RSpec.describe Puma::Enhanced::Stats::Snapshot do
  describe ".cluster" do
    let(:started_at) { Time.utc(2026, 1, 1, 11, 0, 0) }
    let(:phase) { 3 }

    let(:worker) do
      instance_double(
        Puma::Cluster::WorkerHandle,
        index: 0,
        pid: 123,
        phase: 3,
        booted?: true,
        started_at: started_at,
        last_enhanced_checkin: Time.utc(2026, 1, 1, 12, 0, 0),
        last_enhanced_status: {
          stats: default_puma_stats(backlog: 2),
          requests: [{ id: "req" }]
        }
      )
    end

    it "builds worker_status with last_enhanced_status from the enhanced cache" do
      payload = described_class.cluster(workers: [worker], phase: phase, started_at: started_at)

      expect(payload).not_to have_key(:schema_version)
      expect(payload[:worker_status].first[:last_enhanced_status][:backlog]).to eq(2)
      expect(payload[:worker_status].first[:requests].first[:id]).to eq("req")
      expect(payload[:worker_status].first).to include(
        index: 0,
        pid: 123,
        phase: 3,
        booted: true,
        started_at: started_at.iso8601(6)
      )
      expect(payload).to include(
        workers_total: 1,
        workers_reporting: 1,
        workers_stale: 0,
        requests_in_flight: 1,
        backlog_total: 2
      )
      expect(payload.keys.index(:worker_status)).to be > payload.keys.index(:backlog_total)
    end

    it "counts stale workers without last_enhanced_checkin" do
      stale = instance_double(
        Puma::Cluster::WorkerHandle,
        index: 1,
        pid: 456,
        phase: 0,
        booted?: false,
        started_at: started_at,
        last_enhanced_checkin: nil,
        last_enhanced_status: empty_enhanced_status
      )

      payload = described_class.cluster(workers: [worker, stale], phase: phase, started_at: started_at)

      expect(payload[:workers_stale]).to eq(1)
      expect(payload[:workers_reporting]).to eq(1)
    end

    it "defaults missing registry fields" do
      sparse = instance_double(
        Puma::Cluster::WorkerHandle,
        index: 0,
        pid: 789,
        phase: 3,
        booted?: true,
        started_at: started_at,
        last_enhanced_checkin: Time.utc(2026, 1, 1, 12, 0, 0),
        last_enhanced_status: {
          stats: default_puma_stats,
          requests: []
        }
      )

      row = described_class.cluster(workers: [sparse], phase: phase, started_at: started_at)[:worker_status].first

      expect(row[:requests]).to eq([])
      expect(row[:last_enhanced_status][:backlog]).to eq(0)
      expect(row).not_to have_key(:last_checkin)
      expect(row).not_to have_key(:last_status)
    end
  end

  describe ".single" do
    let(:config) { Puma::Enhanced::Stats::Configuration.default }
    let(:server) do
      instance_double(
        Puma::Server,
        stats: default_single_stats(running: 1),
        options: { enhanced_stats: config }
      )
    end

    let(:env) do
      {
        "REQUEST_METHOD" => "GET",
        "PATH_INFO" => "/live",
        "QUERY_STRING" => "",
        "REMOTE_ADDR" => "127.0.0.1",
        "action_dispatch.request_id" => "snapshot-single",
        "puma.enhanced_stats.started_at" => Time.utc(2026, 1, 1, 12, 0, 0).utc.iso8601(6)
      }
    end

    it "reads live registry and server stats" do
      frozen = Time.utc(2026, 1, 1, 12, 0, 0)
      allow(Time).to receive(:now).and_return(frozen)

      with_inflight_env(env) do
        payload = described_class.single(server: server)

        expect(payload[:running]).to eq(1)
        expect(payload[:requests].first[:id]).to eq("snapshot-single")
        expect(payload[:collected_at]).to eq(frozen.iso8601(6))
        expect(payload[:requests_in_flight]).to eq(1)
        expect(payload).not_to have_key(:worker_status)
        expect(payload).not_to have_key(:last_enhanced_checkin)
        expect(payload[:"puma-enhanced-stats"]).to be_nil
        expect(payload[:versions][:"puma-enhanced-stats"]).to eq(Puma::Enhanced::Stats::VERSION)
      end
    end

    it "derives the HTTP payload from Snapshot.server" do
      frozen = Time.utc(2026, 1, 1, 12, 0, 0)
      allow(Time).to receive(:now).and_return(frozen)

      with_inflight_env(env) do
        row = described_class.server(server: server)
        payload = described_class.single(server: server)

        expect(payload[:running]).to eq(row[:stats][:running])
        expect(payload[:requests]).to eq(row[:requests])
      end
    end
  end

  describe ".server" do
    let(:config) { Puma::Enhanced::Stats::Configuration.default }
    let(:server) do
      instance_double(
        Puma::Server,
        stats: default_puma_stats(backlog: 2),
        options: { enhanced_stats: config }
      )
    end

    let(:env) do
      {
        "REQUEST_METHOD" => "GET",
        "PATH_INFO" => "/wire",
        "QUERY_STRING" => "",
        "REMOTE_ADDR" => "127.0.0.1",
        "action_dispatch.request_id" => "wire-row",
        "puma.enhanced_stats.started_at" => Time.utc(2026, 1, 1, 12, 0, 0).utc.iso8601(6)
      }
    end

    it "returns only the worker row without envelope fields" do
      with_inflight_env(env) do
        row = described_class.server(server: server, index: 3)

        expect(row).to include(index: 3, pid: Process.pid)
        expect(row[:stats][:backlog]).to eq(2)
        expect(row[:requests].first[:id]).to eq("wire-row")
        expect(row).not_to have_key(:schema_version)
        expect(row).not_to have_key(:last_checkin)
      end
    end
  end
end
