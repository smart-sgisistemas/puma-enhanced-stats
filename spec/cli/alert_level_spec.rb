# frozen_string_literal: true

require "puma/enhanced/stats/cli/alert_level"

RSpec.describe Puma::Enhanced::Stats::CLI::AlertLevel do
  describe ".aggregate_worker_sync" do
    let(:meta) do
      {
        "collected_at" => "2026-06-12T14:32:01Z",
        "mode" => "cluster",
        "worker_check_interval_seconds" => 5
      }
    end

    it "returns ok when every worker is freshly synced" do
      workers = [
        { "synced_at" => "2026-06-12T14:31:59Z" },
        { "synced_at" => "2026-06-12T14:31:58Z" },
        { "synced_at" => "2026-06-12T14:31:57Z" }
      ]

      result = described_class.aggregate_worker_sync(
        workers,
        collected_at: meta["collected_at"],
        interval_seconds: 5,
        mode: meta["mode"]
      )

      expect(result[:level]).to eq :ok
    end

    it "returns warn when a worker is stale within 2x interval" do
      workers = [{ "synced_at" => "2026-06-12T14:31:53Z" }]

      result = described_class.aggregate_worker_sync(
        workers,
        collected_at: meta["collected_at"],
        interval_seconds: 5,
        mode: meta["mode"]
      )

      expect(result[:level]).to eq :warn
      expect(result[:suffix]).to eq "stale 1"
    end

    it "returns crit when a worker never synced" do
      workers = [{ "synced_at" => nil }]

      result = described_class.aggregate_worker_sync(
        workers,
        collected_at: meta["collected_at"],
        interval_seconds: 5,
        mode: meta["mode"]
      )

      expect(result[:level]).to eq :crit
    end
  end
end
