# frozen_string_literal: true

require "json"
require "rack"

RSpec.describe Puma::App::Status do
  let(:token) { "secret" }
  let(:launcher) do
    double(
      "launcher",
      config: double(options: { enhanced_stats: Puma::Enhanced::Stats::Configuration.new, worker_check_interval: 5 }),
      stats: { backlog: 0, running: 0, pool_capacity: 5, max_threads: 5, requests_count: 0 }
    )
  end

  let(:app) { described_class.new launcher, token: token }

  it "handles built-in control commands" do
    env = Rack::MockRequest.env_for("/gc-stats?token=#{token}")
    status, = app.call(env)
    expect(status).to eq(200)
  end

  it "returns enhanced stats json when authenticated" do
    env = Rack::MockRequest.env_for("/enhanced-stats?token=#{token}")
    status, headers, body = app.call(env)

    expect(status).to eq(200)
    expect(headers["content-type"]).to eq("application/json")
    payload = JSON.parse(body.first)
    expect(payload["schema_version"]).to eq(1)
  end

  it "rejects unauthenticated requests" do
    env = Rack::MockRequest.env_for("/enhanced-stats")
    status, = app.call(env)
    expect(status).to eq(403)
  end
end
