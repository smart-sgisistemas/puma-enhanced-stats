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

  it "aggregates enhanced stats from workers via dedicated pipe sync" do
    2.times { IntegrationServer.trigger_slow_request(@server[:app_port]) }

    payload = nil
    20.times do
      payload = IntegrationServer.fetch_enhanced_stats(
        control_port: @server[:control_port],
        token: @server[:token]
      )
      reporting = payload["workers_reporting"].to_i
      in_flight = payload["requests_in_flight"].to_i
      break if reporting >= 1 && in_flight >= 1

      sleep 1
    end

    expect(payload).not_to have_key("schema_version")
    expect(payload).to include("collected_at", "worker_status", "workers_reporting", "requests_in_flight")
    expect(payload["worker_status"].size).to eq(2)
    expect(payload["workers_reporting"]).to be >= 1
    expect(payload["requests_in_flight"]).to be >= 1
    expect(payload["worker_status"].first).to include("last_enhanced_status", "requests")
    expect(payload["worker_status"].first).not_to have_key("last_checkin")

    validate_schema(payload)
  end

  it "keeps native pumactl stats free of enhanced_stats" do
    sleep 2

    stats = IntegrationServer.fetch_puma_stats(
      control_port: @server[:control_port],
      token: @server[:token]
    )

    expect(stats["worker_status"]).to be_an(Array)
    expect(stats["worker_status"]).not_to be_empty
    stats["worker_status"].each do |worker|
      expect(worker).not_to have_key("enhanced_stats")
    end
  end
end
