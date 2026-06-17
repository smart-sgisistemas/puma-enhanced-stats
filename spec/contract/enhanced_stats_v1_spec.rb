# frozen_string_literal: true

require "json_schemer"

RSpec.describe "enhanced-stats-v1 schema" do
  let(:schema) { JSONSchemer.schema(Pathname.new("schema/enhanced-stats-v1.json")) }
  let(:sample) { JSON.parse(File.read("spec/fixtures/enhanced-stats-v1.sample.json")) }

  it "validates the sample fixture" do
    expect(schema.validate(sample).to_a).to be_empty
  end

  it "rejects payloads without schema_version" do
    invalid = sample.dup
    invalid.delete("schema_version")
    expect(schema.validate(invalid).to_a).not_to be_empty
  end

  it "rejects worker puma stats missing Puma::Server::STAT_METHODS keys" do
    invalid = JSON.parse(JSON.generate(sample))
    invalid["workers"].first["puma"].delete("busy_threads")
    expect(schema.validate(invalid).to_a).not_to be_empty
  end

  it "validates Snapshot.build output for single mode" do
    launcher = instance_double(
      "Launcher",
      config: instance_double("Config", options: { enhanced_stats: Puma::Enhanced::Stats::Configuration.new, worker_check_interval: 5 }),
      stats: {
        backlog: 0,
        running: 0,
        pool_capacity: 5,
        max_threads: 5,
        requests_count: 0,
        last_status: { backlog: 0, running: 0, pool_capacity: 5, max_threads: 5, requests_count: 0 }
      }
    )

    Puma::Enhanced::Stats::CurrentRequests.reset!

    payload = Puma::Enhanced::Stats::Snapshot.build(launcher)
    json = JSON.parse(JSON.generate(payload))

    expect(json["workers"].first["puma"].keys).to match_array(Puma::Server::STAT_METHODS.map(&:to_s))
    expect(schema.validate(json).to_a).to be_empty
  end

  it "validates Snapshot.build output for cluster mode" do
    launcher = begin
      config = Puma::Configuration.new { |user| user.workers 1 }
      instance = Puma::Launcher.new(config)
      allow(instance).to receive(:stats).and_return(
        worker_status: [
          {
            index: 0,
            pid: 123,
            last_status: Puma::Server::STAT_METHODS.to_h { |key| [key, 0] }
          }
        ]
      )
      allow(instance).to receive(:workers).and_return(
        [
          double(
            "WorkerHandle",
            index: 0,
            enhanced_stats: {
              items: [],
              process: Puma::Enhanced::Stats::ProcessMetrics::EMPTY,
              dropped_count: 0,
              truncated: false,
              synced_at: Time.now.utc.iso8601
            }
          )
        ]
      )
      instance
    end

    payload = Puma::Enhanced::Stats::Snapshot.build(launcher)
    json = JSON.parse(JSON.generate(payload))

    expect(json["meta"]["mode"]).to eq("cluster")
    expect(schema.validate(json).to_a).to be_empty
  end
end
