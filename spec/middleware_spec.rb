# frozen_string_literal: true

require "stringio"

RSpec.describe Puma::Enhanced::Stats::Middleware do
  let(:registry) { Puma::Enhanced::Stats::CurrentRequestsRegistry.instance }
  let(:env) { Rack::MockRequest.env_for("/", "REMOTE_ADDR" => "127.0.0.1") }

  before { registry.reset! }

  it "cleans up after exceptions" do
    app = lambda do |_env|
      raise "boom"
    end

    middleware = described_class.new(app, registry: registry)

    expect { middleware.call(env) }.to raise_error("boom")
    expect(registry.snapshot["items"]).to be_empty
  end

  it "cleans up after body is consumed" do
    app = ->(_env) { [200, {}, ["chunk"]] }

    middleware = described_class.new(app, registry: registry)
    _status, _headers, body = middleware.call(env)
    expect(registry.snapshot["items"].size).to eq(1)
    body.each { |_chunk| }
    expect(registry.snapshot["items"]).to be_empty
  end

  it "allows idempotent unregister" do
    app = ->(_env) { [200, {}, ["ok"]] }
    middleware = described_class.new(app, registry: registry)
    _status, _headers, body = middleware.call(env)
    registry.unregister("missing")
    body.each { |c| c }
    expect { registry.unregister("missing") }.not_to raise_error
  end

  it "passes through when registry rejects a new entry" do
    allow(registry).to receive(:register).and_return(nil)
    expect(registry).not_to receive(:unregister)

    app = ->(_env) { [200, {}, ["ok"]] }
    middleware = described_class.new(app, registry: registry)
    status, = middleware.call(env)

    expect(status).to eq(200)
  end

  it "cleans up after rack hijack" do
    app = lambda do |env|
      env["rack.hijack"] = proc { |io| io.close }
      [200, {}, []]
    end
    env["rack.hijack?"] = true

    middleware = described_class.new(app, registry: registry)
    _status, _headers, = middleware.call(env)
    expect(registry.snapshot["items"].size).to eq(1)

    env["rack.hijack"].call(StringIO.new)
    expect(registry.snapshot["items"]).to be_empty
  end

  it "passes through hijack when rack.hijack is not set" do
    app = ->(_env) { [200, {}, []] }
    env["rack.hijack?"] = true

    middleware = described_class.new(app, registry: registry)
    status, _headers, body = middleware.call(env)

    expect(status).to eq(200)
    expect(body).to eq([])
    expect(registry.snapshot["items"].size).to eq(1)
  end

  it "registers an after_reply callback when rack.after_reply is present" do
    app = ->(_env) { [200, {}, ["ok"]] }
    env["rack.after_reply"] = []

    middleware = described_class.new(app, registry: registry)
    _status, _headers, body = middleware.call(env)

    expect(env["rack.after_reply"].size).to eq(1)
    body.each { |chunk| chunk }
    expect(registry.snapshot["items"]).to be_empty
  end
end
