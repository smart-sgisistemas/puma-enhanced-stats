# frozen_string_literal: true

require "puma/enhanced/stats/cli/fetcher"
require "puma/enhanced/stats/cli/options"
require "net/http"

RSpec.describe Puma::Enhanced::Stats::CLI::Fetcher do
  let(:options) do
    Puma::Enhanced::Stats::CLI::Options.new.tap do |opts|
      opts.url = "http://127.0.0.1:9293"
      opts.token = "secret"
    end
  end

  it "fetches enhanced stats over HTTP" do
    payload = { "schema_version" => 1 }
    response = Net::HTTPOK.new("1.1", "200", "OK")
    allow(response).to receive(:body).and_return(payload.to_json)
    allow(Net::HTTP).to receive(:get_response).and_return(response)

    result = described_class.new(options).fetch
    expect(result["schema_version"]).to eq(1)
  end

  it "raises on authentication failure" do
    response = Net::HTTPForbidden.new("1.1", "403", "Forbidden")
    allow(response).to receive(:body).and_return("Invalid auth token")
    allow(Net::HTTP).to receive(:get_response).and_return(response)

    expect { described_class.new(options).fetch }.to raise_error(Puma::Enhanced::Stats::CLI::Fetcher::Error, /403/)
  end

  it "normalizes tcp control URLs" do
    tcp_options = Puma::Enhanced::Stats::CLI::Options.new.tap { |opts| opts.control_url = "tcp://127.0.0.1:9293" }
    payload = { "schema_version" => 1 }
    response = Net::HTTPOK.new("1.1", "200", "OK")
    allow(response).to receive(:body).and_return(payload.to_json)
    expect(Net::HTTP).to receive(:get_response).with(having_attributes(host: "127.0.0.1", port: 9293)).and_return(response)

    expect(described_class.new(tcp_options).fetch["schema_version"]).to eq(1)
  end

  it "reads URL and token from a state file" do
    path = File.join(Dir.tmpdir, "puma-enhanced-stats-fetcher-#{Process.pid}.yml")
    File.write path, <<~YAML
      control_url: http://127.0.0.1:9393
      control_options:
        auth_token: from-state
    YAML
    state_options = Puma::Enhanced::Stats::CLI::Options.new.tap { |opts| opts.state_path = path }
    payload = { "schema_version" => 1 }
    response = Net::HTTPOK.new("1.1", "200", "OK")
    allow(response).to receive(:body).and_return(payload.to_json)
    expect(Net::HTTP).to receive(:get_response).with(having_attributes(port: 9393)).and_return(response)

    expect(described_class.new(state_options).fetch["schema_version"]).to eq(1)
  ensure
    File.delete(path) if path && File.exist?(path)
  end

  it "raises when control URL is missing" do
    expect { described_class.new(Puma::Enhanced::Stats::CLI::Options.new).fetch }
      .to raise_error(Puma::Enhanced::Stats::CLI::Fetcher::Error, /control URL required/)
  end

  it "raises on unsupported schemes and invalid URLs" do
    bad_scheme = Puma::Enhanced::Stats::CLI::Options.new.tap { |opts| opts.control_url = "ftp://127.0.0.1:9293" }
    invalid = Puma::Enhanced::Stats::CLI::Options.new.tap { |opts| opts.control_url = "http://[::1" }

    expect { described_class.new(bad_scheme).fetch }.to raise_error(Puma::Enhanced::Stats::CLI::Fetcher::Error, /unsupported control URL scheme/)
    expect { described_class.new(invalid).fetch }.to raise_error(Puma::Enhanced::Stats::CLI::Fetcher::Error, /invalid control URL/)
  end

  it "raises on HTTP errors and invalid JSON" do
    response = Net::HTTPInternalServerError.new("1.1", "500", "Error")
    allow(response).to receive(:body).and_return("boom")
    allow(Net::HTTP).to receive(:get_response).and_return(response)

    expect { described_class.new(options).fetch }.to raise_error(Puma::Enhanced::Stats::CLI::Fetcher::Error, /HTTP 500/)

    ok = Net::HTTPOK.new("1.1", "200", "OK")
    allow(ok).to receive(:body).and_return("not-json")
    allow(Net::HTTP).to receive(:get_response).and_return(ok)

    expect { described_class.new(options).fetch }.to raise_error(Puma::Enhanced::Stats::CLI::Fetcher::Error, /invalid JSON/)
  end

  it "normalizes ssl control URLs" do
    ssl_options = Puma::Enhanced::Stats::CLI::Options.new.tap { |opts| opts.control_url = "ssl://127.0.0.1:9293" }
    payload = { "schema_version" => 1 }
    response = Net::HTTPOK.new("1.1", "200", "OK")
    allow(response).to receive(:body).and_return(payload.to_json)
    expect(Net::HTTP).to receive(:get_response).with(having_attributes(host: "127.0.0.1", port: 9293)).and_return(response)

    expect(described_class.new(ssl_options).fetch["schema_version"]).to eq(1)
  end

  it "fetches without a token when none is configured" do
    tokenless = Puma::Enhanced::Stats::CLI::Options.new.tap { |opts| opts.url = "http://127.0.0.1:9293" }
    payload = { "schema_version" => 1 }
    response = Net::HTTPOK.new("1.1", "200", "OK")
    allow(response).to receive(:body).and_return(payload.to_json)
    allow(Net::HTTP).to receive(:get_response).and_return(response)

    expect(described_class.new(tokenless).fetch["schema_version"]).to eq(1)
  end

  it "normalizes control URLs with a trailing slash" do
    slash_options = Puma::Enhanced::Stats::CLI::Options.new.tap { |opts| opts.url = "http://127.0.0.1:9293/" }
    payload = { "schema_version" => 1 }
    response = Net::HTTPOK.new("1.1", "200", "OK")
    allow(response).to receive(:body).and_return(payload.to_json)
    expect(Net::HTTP).to receive(:get_response).with(having_attributes(request_uri: "/enhanced-stats")).and_return(response)

    expect(described_class.new(slash_options).fetch["schema_version"]).to eq(1)
  end

  it "exposes master pid from the state file" do
    path = File.join(Dir.tmpdir, "puma-enhanced-stats-master-#{Process.pid}.yml")
    File.write path, <<~YAML
      pid: 7777
      control_url: http://127.0.0.1:9393
    YAML
    state_options = Puma::Enhanced::Stats::CLI::Options.new.tap { |opts| opts.state_path = path }

    expect(described_class.new(state_options).master_pid).to eq(7777)
  ensure
    File.delete(path) if path && File.exist?(path)
  end

  it "returns nil master pid when no state file is configured" do
    expect(described_class.new(options).master_pid).to be_nil
  end
end
