# frozen_string_literal: true

require "json_schemer"
require "pathname"

RSpec.describe "cluster mode control app", :integration do
  include RSpec::Matchers

  def validate_schema payload
    schema = JSONSchemer.schema(Pathname.new("schema/enhanced-stats-v1.json"))
    expect(schema.validate(payload).to_a).to be_empty
  end

  around do |example|
    server = IntegrationServer.start_puma_server(
      workers: 2,
      worker_check_interval: 2,
      slow_sleep: 20
    )
    @server = server
    example.run
  ensure
    IntegrationServer.stop_puma_server(server)
  end

  it "aggregates enhanced stats from workers via ping sync" do
    2.times { IntegrationServer.trigger_slow_request(@server[:app_port]) }
    sleep Puma::Enhanced::Stats::Configuration.default.sync_interval + 4

    payload = IntegrationServer.fetch_enhanced_stats(
      control_port: @server[:control_port],
      token: @server[:token]
    )

    expect(payload["schema_version"]).to eq(1)
    expect(payload["meta"]["mode"]).to eq("cluster")
    expect(payload["workers"].size).to eq(2)
    expect(payload["workers"].map { |w| w["synced_at"] }).to all(satisfy { |value| !value.nil? && !value.empty? })
    expect(payload["workers"].sum { |w| w.dig("puma", "requests_count") || 0 }).to be >= 1

    validate_schema(payload)
  end
end
