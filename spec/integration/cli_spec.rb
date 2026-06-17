# frozen_string_literal: true

require "shellwords"
require "json"
require "fileutils"

RSpec.describe "puma-enhanced-stats CLI", :integration do
  def with_puma_config
    Dir.mktmpdir("puma-enhanced-stats-cli-config-") do |dir|
      FileUtils.mkdir_p File.join(dir, "config")
      File.write File.join(dir, "config/puma.rb"), <<~RUBY
        activate_control_app "tcp://127.0.0.1:#{@server[:control_port]}", auth_token: "#{@server[:token]}"
      RUBY
      Dir.chdir(dir) { yield }
    end
  end

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

    output = nil
    with_puma_config do
      cmd = ["bundle", "exec", "puma-enhanced-stats", "-C", "-w", "100"]
      output = `#{Shellwords.shelljoin(cmd)} 2>&1`
    end

    expect($?.success?).to be(true), output
    expect(output).to include("PUMA ENHANCED STATS")
    expect(output).to include("SYSTEM")
    expect(output).to include("SUMMARY")
    expect(output).to include("WORKER 0")
    expect(output).to include("/slow")
  end

  it "prints json with --json" do
    output = nil
    with_puma_config do
      cmd = ["bundle", "exec", "puma-enhanced-stats", "--json"]
      output = `#{Shellwords.shelljoin(cmd)} 2>&1`
    end
    payload = JSON.parse(output)

    expect(payload["schema_version"]).to eq(1)
    IntegrationServer.validate_against_schema(payload)
  end

  it "connects without flags when config/puma.rb is present" do
    output = nil
    success = nil
    with_puma_config do
      cmd = ["bundle", "exec", "puma-enhanced-stats", "--json"]
      output = `#{Shellwords.shelljoin(cmd)} 2>&1`
      success = $?.success?
    end

    expect(success).to be(true), output
    expect(JSON.parse(output)["schema_version"]).to eq(1)
  end

  it "renders request-only output" do
    IntegrationServer.trigger_slow_request(@server[:app_port])
    sleep 0.5

    output = nil
    with_puma_config do
      cmd = ["bundle", "exec", "puma-enhanced-stats", "--request-only", "-C", "-w", "100"]
      output = `#{Shellwords.shelljoin(cmd)} 2>&1`
    end

    expect($?.success?).to be(true), output
    expect(output).to include("WORKERS")
    expect(output).to include("WORKER 0")
    expect(output).to include("/slow")
    expect(output).not_to include("PUMA ENHANCED STATS")
  end
end
