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

  it "validates Snapshot.build output for single mode" do
    launcher = instance_double(
      "Launcher",
      config: instance_double("Config", options: { enhanced_stats: Puma::Enhanced::Stats::Configuration.new, worker_check_interval: 5 }),
      stats_hash: {
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
    expect(schema.validate(payload).to_a).to be_empty
  end
end
