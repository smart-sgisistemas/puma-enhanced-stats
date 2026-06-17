# frozen_string_literal: true

RSpec.describe Puma::Enhanced::Stats::RequestsMiddleware do
  let(:current_requests) { Puma::Enhanced::Stats::CurrentRequests }
  let(:env) do
    Rack::MockRequest.env_for("/", "REMOTE_ADDR" => "127.0.0.1").merge(
      "action_dispatch.request_id" => "middleware-request-id"
    )
  end

  before do
    current_requests.reset!
    current_requests.config = Puma::Enhanced::Stats::Configuration.new
  end

  it "cleans up after exceptions" do
    app = lambda do |_env|
      raise "boom"
    end

    middleware = described_class.new(app)

    expect { middleware.call(env) }.to raise_error("boom")
    expect(current_requests.snapshot[:items]).to be_empty
  end

  it "unregisters when the app returns without waiting for the body" do
    app = ->(_env) { [200, {}, ["chunk"]] }

    middleware = described_class.new(app)
    _status, _headers, body = middleware.call(env)

    expect(current_requests.snapshot[:items]).to be_empty
    expect(body).to eq(["chunk"])
  end

  it "allows idempotent unregister" do
    app = ->(_env) { [200, {}, ["ok"]] }
    middleware = described_class.new(app)
    middleware.call(env)

    expect { current_requests.unregister env.merge("action_dispatch.request_id" => "missing-request") }.not_to raise_error
  end

  it "passes through when registry rejects a new entry" do
    allow(current_requests).to receive(:register)

    app = ->(_env) { [200, {}, ["ok"]] }
    middleware = described_class.new(app)
    status, = middleware.call(env)

    expect(status).to eq(200)
  end

  it "continues when register fails" do
    current_requests.config = Puma::Enhanced::Stats::Configuration.new.tap do |configuration|
      configuration.register_fields :request, :boom do |_env|
        raise "stats down"
      end
    end

    app = ->(_env) { [200, {}, ["ok"]] }
    status, _headers, body = described_class.new(app).call(env)

    expect(status).to eq(200)
    expect(body).to eq(["ok"])
  end

  it "unregisters when the app returns, including rack hijack" do
    app = lambda do |env|
      env["rack.hijack"] = proc { |io| io.close }
      [200, {}, []]
    end
    env["rack.hijack?"] = true

    middleware = described_class.new(app)
    middleware.call(env)

    expect(current_requests.snapshot[:items]).to be_empty
  end

  it "unregisters when hijack app call raises" do
    app = lambda do |_env|
      raise "hijack boom"
    end
    env["rack.hijack?"] = true

    middleware = described_class.new(app)

    expect { middleware.call(env) }.to raise_error("hijack boom")
    expect(current_requests.snapshot[:items]).to be_empty
  end

  it "unregisters when hijack capable but rack.hijack is not set" do
    app = ->(_env) { [200, {}, []] }
    env["rack.hijack?"] = true

    middleware = described_class.new(app)
    status, _headers, body = middleware.call(env)

    expect(status).to eq(200)
    expect(body).to eq([])
    expect(current_requests.snapshot[:items]).to be_empty
  end
end
