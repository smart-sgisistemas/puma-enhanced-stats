# frozen_string_literal: true

require "puma/enhanced/stats/cli/fetcher"
require "net/http"

RSpec.describe Puma::Enhanced::Stats::CLI::Fetcher do
  def stub_discovery control_url:, token: "secret", master_pid: nil, state_path: nil
    allow(Puma::Enhanced::Stats::CLI::ControlDiscovery).to receive(:resolve).and_return(
      Puma::Enhanced::Stats::CLI::ControlDiscovery::Entry.new(
        control_url: control_url,
        token: token,
        master_pid: master_pid,
        state_path: state_path
      )
    )
  end

  before do
    stub_discovery control_url: "http://127.0.0.1:9293"
  end

  it "fetches enhanced stats over HTTP" do
    payload = { "schema_version" => 1 }
    response = Net::HTTPOK.new("1.1", "200", "OK")
    allow(response).to receive(:body).and_return(payload.to_json)
    allow(Net::HTTP).to receive(:get_response).and_return(response)

    result = described_class.new.fetch
    expect(result["schema_version"]).to eq(1)
  end

  it "raises on authentication failure" do
    response = Net::HTTPForbidden.new("1.1", "403", "Forbidden")
    allow(response).to receive(:body).and_return("Invalid auth token")
    allow(Net::HTTP).to receive(:get_response).and_return(response)

    expect { described_class.new.fetch }.to raise_error(Puma::Enhanced::Stats::CLI::Fetcher::Error, /403/)
  end

  it "normalizes tcp control URLs" do
    stub_discovery control_url: "tcp://127.0.0.1:9293", token: nil
    payload = { "schema_version" => 1 }
    response = Net::HTTPOK.new("1.1", "200", "OK")
    allow(response).to receive(:body).and_return(payload.to_json)
    expect(Net::HTTP).to receive(:get_response).with(having_attributes(host: "127.0.0.1", port: 9293)).and_return(response)

    expect(described_class.new.fetch["schema_version"]).to eq(1)
  end

  it "reads URL and token from discovery" do
    stub_discovery control_url: "http://127.0.0.1:9393", token: "from-discovery"
    payload = { "schema_version" => 1 }
    response = Net::HTTPOK.new("1.1", "200", "OK")
    allow(response).to receive(:body).and_return(payload.to_json)
    expect(Net::HTTP).to receive(:get_response).with(having_attributes(port: 9393)).and_return(response)

    expect(described_class.new.fetch["schema_version"]).to eq(1)
  end

  it "raises when control URL is missing" do
    stub_discovery control_url: nil, token: nil

    expect { described_class.new.fetch }
      .to raise_error(Puma::Enhanced::Stats::CLI::Fetcher::Error, /control URL required/)
  end

  it "raises on unsupported schemes and invalid URLs" do
    stub_discovery control_url: "ftp://127.0.0.1:9293", token: nil
    expect { described_class.new.fetch }.to raise_error(Puma::Enhanced::Stats::CLI::Fetcher::Error, /unsupported control URL scheme/)

    stub_discovery control_url: "http://[::1", token: nil
    expect { described_class.new.fetch }.to raise_error(Puma::Enhanced::Stats::CLI::Fetcher::Error, /invalid control URL/)
  end

  it "raises on HTTP errors and invalid JSON" do
    response = Net::HTTPInternalServerError.new("1.1", "500", "Error")
    allow(response).to receive(:body).and_return("boom")
    allow(Net::HTTP).to receive(:get_response).and_return(response)

    expect { described_class.new.fetch }.to raise_error(Puma::Enhanced::Stats::CLI::Fetcher::Error, /HTTP 500/)

    ok = Net::HTTPOK.new("1.1", "200", "OK")
    allow(ok).to receive(:body).and_return("not-json")
    allow(Net::HTTP).to receive(:get_response).and_return(ok)

    expect { described_class.new.fetch }.to raise_error(Puma::Enhanced::Stats::CLI::Fetcher::Error, /invalid JSON/)
  end

  it "normalizes ssl control URLs" do
    stub_discovery control_url: "ssl://127.0.0.1:9293", token: nil
    payload = { "schema_version" => 1 }
    response = Net::HTTPOK.new("1.1", "200", "OK")
    allow(response).to receive(:body).and_return(payload.to_json)
    expect(Net::HTTP).to receive(:get_response).with(having_attributes(host: "127.0.0.1", port: 9293)).and_return(response)

    expect(described_class.new.fetch["schema_version"]).to eq(1)
  end

  it "fetches without a token when none is configured" do
    stub_discovery control_url: "http://127.0.0.1:9293", token: nil
    payload = { "schema_version" => 1 }
    response = Net::HTTPOK.new("1.1", "200", "OK")
    allow(response).to receive(:body).and_return(payload.to_json)
    allow(Net::HTTP).to receive(:get_response).and_return(response)

    expect(described_class.new.fetch["schema_version"]).to eq(1)
  end

  it "normalizes control URLs with a trailing slash" do
    stub_discovery control_url: "http://127.0.0.1:9293/", token: nil
    payload = { "schema_version" => 1 }
    response = Net::HTTPOK.new("1.1", "200", "OK")
    allow(response).to receive(:body).and_return(payload.to_json)
    expect(Net::HTTP).to receive(:get_response).with(having_attributes(request_uri: "/enhanced-stats")).and_return(response)

    expect(described_class.new.fetch["schema_version"]).to eq(1)
  end

  it "exposes master pid from discovery" do
    stub_discovery control_url: "http://127.0.0.1:9393", token: nil, master_pid: 7777

    expect(described_class.new.master_pid).to eq(7777)
  end

  it "returns nil master pid when discovery has none" do
    stub_discovery control_url: "http://127.0.0.1:9293", token: nil, master_pid: nil

    expect(described_class.new.master_pid).to be_nil
  end
end
