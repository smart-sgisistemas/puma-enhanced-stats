# frozen_string_literal: true

require "puma/enhanced/stats"

RSpec.describe Puma::Enhanced::Stats::Snapshot do
  def default_stats **overrides
    Puma::Server::STAT_METHODS.to_h { |key| [key, 0] }.merge(overrides)
  end

  describe "#to_h" do
    context "cluster mode" do
      let(:worker) do
        instance_double(
          Puma::Cluster::WorkerHandle,
          index: 0,
          pid: 123,
          last_enhanced_stats: default_stats(backlog: 2).merge(
            items: [{ id: "req" }],
            dropped_count: 1,
            truncated: true,
            synced_at: "2026-01-01T12:00:00Z"
          )
        )
      end

      it "builds workers with puma stats from the enhanced cache" do
        payload = described_class.new(workers: [worker], worker_check_interval: 5).to_h

        expect(payload[:schema_version]).to eq(1)
        expect(payload[:meta][:mode]).to eq("cluster")
        expect(payload[:workers].first[:puma][:backlog]).to eq(2)
        expect(payload[:workers].first[:requests][:items].first[:id]).to eq("req")
        expect(payload[:summary]).to include(
          workers_total: 1,
          workers_reporting: 1,
          workers_stale: 0,
          requests_in_flight: 1,
          requests_dropped_total: 1,
          requests_truncated: true,
          backlog_total: 2
        )
      end

      it "counts stale workers without synced_at" do
        stale = instance_double(
          Puma::Cluster::WorkerHandle,
          index: 1,
          pid: 456,
          last_enhanced_stats: Puma::Enhanced::Stats::WorkerHandle::EMPTY_ENHANCED_STATS.dup
        )

        payload = described_class.new(workers: [worker, stale], worker_check_interval: 5).to_h

        expect(payload[:summary][:workers_stale]).to eq(1)
        expect(payload[:summary][:workers_reporting]).to eq(1)
      end

      it "defaults missing registry fields" do
        sparse = instance_double(
          Puma::Cluster::WorkerHandle,
          index: 2,
          pid: 789,
          last_enhanced_stats: { synced_at: "2026-01-01T12:00:00Z" }
        )

        row = described_class.new(workers: [sparse], worker_check_interval: 5).to_h[:workers].first

        expect(row[:requests][:items]).to eq([])
        expect(row[:requests][:meta][:truncated]).to be(false)
        expect(row[:requests][:meta][:dropped_count]).to eq(0)
        expect(row[:puma][:backlog]).to eq(0)
      end
    end

    context "single mode" do
      let(:server) { instance_double(Puma::Server, stats: default_stats(running: 1)) }

      before do
        Puma::Enhanced::Stats::CurrentRequests.reset!
        Puma::Enhanced::Stats::CurrentRequests.register(
          "REQUEST_METHOD" => "GET",
          "PATH_INFO" => "/live",
          "QUERY_STRING" => "",
          "REMOTE_ADDR" => "127.0.0.1",
          "action_dispatch.request_id" => "snapshot-single"
        )
      end

      it "reads live registry and server stats" do
        frozen = Time.utc(2026, 1, 1, 12, 0, 0)
        allow(Time).to receive(:now).and_return(frozen)

        payload = described_class.new(server: server, worker_check_interval: 0).to_h

        expect(payload[:meta][:mode]).to eq("single")
        expect(payload[:meta][:worker_check_interval_seconds]).to eq(0)
        expect(payload[:workers].first[:puma][:running]).to eq(1)
        expect(payload[:workers].first[:requests][:items].first[:id]).to eq("snapshot-single")
        expect(payload[:workers].first[:synced_at]).to eq(payload[:meta][:collected_at])
      end
    end
  end
end
