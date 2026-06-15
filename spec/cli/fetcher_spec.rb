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
end
