# frozen_string_literal: true

RSpec.describe Puma::Enhanced::Stats::Normalizer do
  let(:config) { Puma::Enhanced::Stats::Configuration.new }
  let(:now) { Time.utc(2026, 6, 12, 10, 0, 2) }

  describe ".item_with_elapsed" do
    it "calculates elapsed_ms from started_at" do
      item = { "id" => "a", "started_at" => "2026-06-12T10:00:00Z", "method" => "GET" }
      result = described_class.item_with_elapsed(item, now)

      expect(result["elapsed_ms"]).to eq(2000)
    end

    it "calculates elapsed_ms even when a custom elapsed_ms field is registered" do
      custom = Puma::Enhanced::Stats::Configuration.new
      Puma::Enhanced::Stats::DSL::Builder.new(custom).instance_eval do
        request :elapsed_ms do |_env|
          999
        end
      end

      item = { "id" => "a", "started_at" => "2026-06-12T10:00:00Z", "elapsed_ms" => 999 }
      result = described_class.item_with_elapsed(item, now)

      expect(result["elapsed_ms"]).to eq(2000)
    end

    it "returns nil elapsed_ms for invalid started_at" do
      item = { "id" => "a", "started_at" => "not-a-time" }
      result = described_class.item_with_elapsed(item, now)

      expect(result["elapsed_ms"]).to be_nil
    end
  end

  describe ".pick_puma_stats" do
    it "normalizes symbol and string keys" do
      stats = described_class.pick_puma_stats(
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
      expect(described_class.normalize_process(rss_bytes: 100, cpu_percent: 1.5)).to eq(
        "rss_bytes" => 100,
        "cpu_percent" => 1.5
      )
    end

    it "returns EMPTY when raw is nil" do
      expect(described_class.normalize_process(nil)).to eq(Puma::Enhanced::Stats::ProcessMetrics::EMPTY)
    end
  end

  describe ".requests_section" do
    it "builds requests meta and items" do
      section = described_class.requests_section(
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

      summary = described_class.summary(workers)

      expect(summary).to eq(
        "workers_total" => 2,
        "workers_reporting" => 1,
        "requests_in_flight" => 3,
        "requests_dropped_total" => 1
      )
    end
  end
end
