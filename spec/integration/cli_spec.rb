# frozen_string_literal: true

require "shellwords"
require "json"

RSpec.describe "puma-enhanced-stats CLI", :integration do
  around do |example|
    server = IntegrationServer.start_puma_server
    @server = server
    example.run
  ensure
    IntegrationServer.stop_puma_server(server)
  end

  it "renders dashboard output" do
    IntegrationServer.trigger_slow_request(@server[:app_port])
    sleep 0.5

    cmd = [
      "bundle", "exec", "puma-enhanced-stats",
      "--url", "http://127.0.0.1:#{@server[:control_port]}",
      "--token", @server[:token],
      "--no-color",
      "--width", "100"
    ]
    output = `#{Shellwords.shelljoin(cmd)} 2>&1`

    expect($?.success?).to be(true), output
    expect(output).to include("PUMA ENHANCED STATS")
    expect(output).to include("SUMMARY")
    expect(output).to include("WORKER 0")
    expect(output).to include("/slow")
  end

  it "prints json with --json" do
    cmd = [
      "bundle", "exec", "puma-enhanced-stats",
      "--url", "http://127.0.0.1:#{@server[:control_port]}",
      "--token", @server[:token],
      "--json"
    ]
    output = `#{Shellwords.shelljoin(cmd)} 2>&1`
    payload = JSON.parse(output)

    expect(payload["schema_version"]).to eq(1)
    IntegrationServer.validate_against_schema(payload)
  end
end
