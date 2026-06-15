# frozen_string_literal: true

require "json"
require "json_schemer"
require "pathname"

RSpec.describe "pumactl enhanced-stats", :integration do
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

  it "prints valid enhanced stats json" do
    IntegrationServer.trigger_slow_request(@server[:app_port])
    sleep 0.5

    control_url = "tcp://127.0.0.1:#{@server[:control_port]}"
    output, success = IntegrationServer.run_pumactl(
      control_url: control_url,
      token: @server[:token],
      command: "enhanced-stats"
    )
    expect(success).to be(true), output

    payload = JSON.parse(output[output.index("{")..])
    expect(payload["schema_version"]).to eq(1)
    validate_schema(payload)
  end
end
