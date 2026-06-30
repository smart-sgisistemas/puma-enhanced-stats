# frozen_string_literal: true

require "json"
require "json_schemer"
require "pathname"

RSpec.describe "single mode control app", :integration do
  include RSpec::Matchers

  def validate_schema payload
    schema = JSONSchemer.schema(Pathname.new("schema/enhanced-stats-v1.json"))
    expect(schema.validate(payload).to_a).to be_empty
  end
  around do |example|
    server = IntegrationServer.start_puma_server(slow_sleep: 20)
    @server = server
    example.run
  ensure
    IntegrationServer.stop_puma_server(server)
  end

  it "returns in-flight requests from GET /enhanced-stats" do
    IntegrationServer.trigger_slow_request(@server[:app_port])

    payload = nil
    20.times do
      payload = IntegrationServer.fetch_enhanced_stats(
        control_port: @server[:control_port],
        token: @server[:token]
      )
      break if payload["requests_in_flight"].to_i >= 1

      sleep 0.25
    end

    expect(payload).not_to have_key("schema_version")
    expect(payload).to include("collected_at", "requests", "requests_in_flight", "versions")
    expect(payload).not_to have_key("worker_status")

    items = payload["requests"]
    expect(items).to include(hash_including("method" => "GET", "path_info" => match(%r{/slow\z})))

    validate_schema(payload)
  end
end
