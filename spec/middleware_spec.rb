# frozen_string_literal: true

RSpec.describe Puma::Enhanced::Stats::Middleware do
  let(:middleware_key) { described_class::KEY }
  let(:env) do
    Rack::MockRequest.env_for("/", "REMOTE_ADDR" => "127.0.0.1").merge(
      "action_dispatch.request_id" => "middleware-request-id"
    )
  end

  def inflight_env_on_current_thread
    Thread.current[middleware_key]
  end

  it "cleans up after exceptions" do
    app = lambda do |_env|
      raise "boom"
    end

    middleware = described_class.new(app)

    expect { middleware.call(env) }.to raise_error("boom")
    expect(inflight_env_on_current_thread).to be_nil
  end

  it "stores env on the current thread during the request" do
    app = lambda do |request_env|
      expect(inflight_env_on_current_thread).to equal(request_env)
      expect(request_env[described_class::STARTED_AT_KEY]).to match(/\A\d{4}-\d{2}-\d{2}T/)
      [200, {}, ["ok"]]
    end

    described_class.new(app).call(env)
    expect(inflight_env_on_current_thread).to be_nil
  end

  it "unregisters when the app returns without waiting for the body" do
    app = ->(_env) { [200, {}, ["chunk"]] }

    middleware = described_class.new(app)
    _status, _headers, body = middleware.call(env)

    expect(inflight_env_on_current_thread).to be_nil
    expect(body).to eq(["chunk"])
  end

  it "continues when downstream app succeeds" do
    app = ->(_env) { [200, {}, ["ok"]] }
    status, _headers, body = described_class.new(app).call(env)

    expect(status).to eq(200)
    expect(body).to eq(["ok"])
  end

  it "unregisters when the app returns, including rack hijack" do
    app = lambda do |request_env|
      request_env["rack.hijack"] = proc { |io| io.close }
      [200, {}, []]
    end
    env["rack.hijack?"] = true

    described_class.new(app).call(env)

    expect(inflight_env_on_current_thread).to be_nil
  end

  it "unregisters when hijack app call raises" do
    app = lambda do |_env|
      raise "hijack boom"
    end
    env["rack.hijack?"] = true

    expect { described_class.new(app).call(env) }.to raise_error("hijack boom")
    expect(inflight_env_on_current_thread).to be_nil
  end
end
