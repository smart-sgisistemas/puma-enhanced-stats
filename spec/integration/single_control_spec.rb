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
    server = IntegrationServer.start_puma_server
    @server = server
    example.run
  ensure
    IntegrationServer.stop_puma_server(server)
  end

  it "returns in-flight requests from GET /enhanced-stats" do
    IntegrationServer.trigger_slow_request(@server[:app_port])
    sleep 0.5

    payload = IntegrationServer.fetch_enhanced_stats(
      control_port: @server[:control_port],
      token: @server[:token]
    )

    expect(payload["schema_version"]).to eq(1)
    expect(payload["meta"]["mode"]).to eq("single")
    expect(payload["workers"].size).to eq(1)

    items = payload["workers"].first["requests"]["items"]
    expect(items).to include(hash_including("method" => "GET", "path_info" => match(%r{/slow\z})))

    validate_schema(payload)
  end
end
