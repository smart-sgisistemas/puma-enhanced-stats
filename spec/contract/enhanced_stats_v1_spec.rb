# frozen_string_literal: true

require "json_schemer"

RSpec.describe "enhanced-stats-v1 schema" do
  let(:schema) { JSONSchemer.schema(Pathname.new("schema/enhanced-stats-v1.json")) }
  let(:cluster_sample) { JSON.parse(File.read("spec/fixtures/enhanced-stats-v1.sample.json")) }

  it "validates the cluster sample fixture" do
    expect(schema.validate(cluster_sample).to_a).to be_empty
  end

  it "rejects cluster payloads missing last_enhanced_status keys" do
    invalid = JSON.parse(JSON.generate(cluster_sample))
    invalid["worker_status"].first["last_enhanced_status"].delete("busy_threads")
    expect(schema.validate(invalid).to_a).not_to be_empty
  end

  it "rejects request items without session" do
    invalid = JSON.parse(JSON.generate(cluster_sample))
    invalid["worker_status"].first["requests"].first.delete("session")
    expect(schema.validate(invalid).to_a).not_to be_empty
  end

  it "rejects legacy envelope fields" do
    invalid = cluster_sample.merge("schema_version" => 1)
    expect(schema.validate(invalid).to_a).not_to be_empty
  end

  it "validates launcher.enhanced_stats output for cluster mode" do
    launcher = Puma::Launcher.new(Puma::Configuration.new { |user| user.workers 1 })
    allow(launcher.instance_variable_get(:@runner)).to receive(:enhanced_stats).and_return(
      started_at: Time.now.utc.iso8601,
      workers: 1,
      phase: 0,
      booted_workers: 1,
      old_workers: 0,
      collected_at: Time.now.utc.iso8601,
      workers_total: 1,
      workers_reporting: 1,
      workers_stale: 0,
      requests_in_flight: 0,
      backlog_total: 0,
      busy_threads_total: 0,
      max_threads_total: 0,
      pool_capacity_total: 0,
      worker_status: [
        enhanced_worker_status_row(index: 0, pid: 123, phase: 3, last_enhanced_checkin: Time.now.utc.iso8601)
      ],
      versions: {
        puma: Puma::Const::PUMA_VERSION,
        "puma-enhanced-stats": Puma::Enhanced::Stats::VERSION,
        ruby: {
          engine: RUBY_ENGINE,
          version: RUBY_VERSION,
          patchlevel: RUBY_PATCHLEVEL
        }
      }
    )

    json = JSON.parse(JSON.generate(launcher.enhanced_stats))

    expect(json).not_to have_key("schema_version")
    expect(schema.validate(json).to_a).to be_empty
  end
end
