# frozen_string_literal: true

RSpec.describe Puma::Enhanced::Stats::RequestStartMiddleware do
  let(:app) { ->(env) { [200, {"X-Start" => env["HTTP_X_REQUEST_START"]}, []] } }
  let(:middleware) { described_class.new(app) }

  it "sets HTTP_X_REQUEST_START when missing" do
    env = Rack::MockRequest.env_for("/")
    frozen = Time.utc(2024, 6, 14, 12, 0, 0)
    allow(Time).to receive(:now).and_return(frozen)

    _status, headers, = middleware.call(env)

    expect(headers["X-Start"]).to eq("t=#{frozen.to_f}")
  end

  it "sets HTTP_X_REQUEST_START when blank" do
    env = Rack::MockRequest.env_for("/", "HTTP_X_REQUEST_START" => "  ")
    frozen = Time.utc(2024, 6, 14, 12, 0, 0)
    allow(Time).to receive(:now).and_return(frozen)

    _status, headers, = middleware.call(env)

    expect(headers["X-Start"]).to eq("t=#{frozen.to_f}")
  end

  it "preserves an existing HTTP_X_REQUEST_START" do
    env = Rack::MockRequest.env_for("/", "HTTP_X_REQUEST_START" => "t=1718381234.567")

    _status, headers, = middleware.call(env)

    expect(headers["X-Start"]).to eq("t=1718381234.567")
  end
end
