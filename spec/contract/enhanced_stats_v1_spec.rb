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

  it "rejects request items without session" do
    invalid = JSON.parse(JSON.generate(sample))
    invalid["workers"].first["requests"]["items"].first.delete("session")
    expect(schema.validate(invalid).to_a).not_to be_empty
  end

  it "validates launcher.enhanced_stats output for single mode" do
    launcher = Puma::Launcher.new(Puma::Configuration.new { |user| user.worker_check_interval 5 })

    Puma::Enhanced::Stats::CurrentRequests.reset!

    env = {
      "REQUEST_METHOD" => "GET",
      "PATH_INFO" => "/",
      "REMOTE_ADDR" => "127.0.0.1",
      "action_dispatch.request_id" => "contract-request-id"
    }
    Puma::Enhanced::Stats::CurrentRequests.register(env)

    json = JSON.parse(JSON.generate(launcher.enhanced_stats))

    expect(json["meta"]["worker_check_interval_seconds"]).to eq(0)
    expect(json["workers"].first["puma"].keys).to match_array(Puma::Server::STAT_METHODS.map(&:to_s))
    expect(json["workers"].first["requests"]["items"].first["session"]).to eq({})
    expect(schema.validate(json).to_a).to be_empty

    Puma::Enhanced::Stats::CurrentRequests.reset!
  end

  it "validates launcher.enhanced_stats output for cluster mode" do
    launcher = Puma::Launcher.new(Puma::Configuration.new { |user| user.workers 1 })
    allow(launcher.instance_variable_get(:@runner)).to receive(:enhanced_stats).and_return(
      schema_version: 1,
      meta: {
        collected_at: Time.now.utc.iso8601,
        gem_version: Puma::Enhanced::Stats::VERSION,
        puma_version: Puma::Const::PUMA_VERSION,
        ruby_version: RUBY_VERSION,
        mode: "cluster",
        worker_check_interval_seconds: 5
      },
      summary: {
        workers_total: 1,
        workers_reporting: 1,
        workers_stale: 0,
        requests_in_flight: 0,
        requests_dropped_total: 0,
        requests_truncated: false,
        backlog_total: 0,
        busy_threads_total: 0,
        max_threads_total: 0,
        pool_capacity_total: 0
      },
      workers: [
        {
          index: 0,
          pid: 123,
          synced_at: Time.now.utc.iso8601,
          puma: Puma::Server::STAT_METHODS.to_h { |key| [key, 0] },
          requests: {
            meta: {
              count: 0,
              request_limit: 100,
              limit_policy: "keep_longest",
              truncated: false,
              dropped_count: 0
            },
            items: []
          }
        }
      ]
    )

    json = JSON.parse(JSON.generate(launcher.enhanced_stats))

    expect(json["meta"]["mode"]).to eq("cluster")
    expect(schema.validate(json).to_a).to be_empty
  end
end
