# frozen_string_literal: true

RSpec.describe Puma::Enhanced::Stats::CurrentRequests do
  subject(:registry) { described_class.instance }

  let(:env) do
    {
      "REQUEST_METHOD" => "GET",
      "PATH_INFO" => "/",
      "QUERY_STRING" => "",
      "REMOTE_ADDR" => "127.0.0.1"
    }
  end

  before do
    registry.reset!
    registry.config = Puma::Enhanced::Stats::Configuration.new.tap do |configuration|
      configuration.request_limit = 2
    end
  end

  it "registers and unregisters entries" do
    id = registry.register(env)
    expect(registry.snapshot["items"].size).to eq(1)
    registry.unregister(id)
    expect(registry.snapshot["items"]).to be_empty
  end

  it "evicts newest entry with keep_longest policy" do
    registry.config.limit_policy = :keep_longest

    first = registry.register(env.merge("PATH_INFO" => "/first"))
    sleep 0.01
    second = registry.register(env.merge("PATH_INFO" => "/second"))
    sleep 0.01
    third = registry.register(env.merge("PATH_INFO" => "/third"))

    snapshot = registry.snapshot
    paths = snapshot["items"].map { |item| item["path_info"] }
    expect(paths.none? { |path| path.end_with?("/second") })
    expect(snapshot["dropped_count"]).to eq(1)
    expect(paths.any? { |path| path.end_with?("/first") }).to be(true)
    expect(paths.any? { |path| path.end_with?("/third") }).to be(true)
    registry.unregister(first)
    registry.unregister(third)
  end

  it "rejects new entries when policy is reject_new" do
    registry.config.limit_policy = :reject_new

    2.times { registry.register(env) }
    registry.register(env.merge("PATH_INFO" => "/rejected"))

    snapshot = registry.snapshot
    expect(snapshot["items"].size).to eq(2)
    expect(snapshot["dropped_count"]).to eq(1)
  end

  it "replaces duplicate request ids and increments dropped_count" do
    shared_id = "same-request-id"
    registry.register env.merge("action_dispatch.request_id" => shared_id, "PATH_INFO" => "/first")
    registry.register env.merge("action_dispatch.request_id" => shared_id, "PATH_INFO" => "/second")

    snapshot = registry.snapshot
    expect(snapshot["items"].size).to eq(1)
    expect(snapshot["items"].first["path_info"]).to end_with("/second")
    expect(snapshot["dropped_count"]).to eq(1)
  end

  it "registers another request while a slow extractor runs" do
    slow_config = Puma::Enhanced::Stats::Configuration.new.tap do |configuration|
      configuration.request_limit = 10
      configuration.register_fields :request, :slow_path do |env|
        sleep 0.15 if env["PATH_INFO"] == "/slow"
        env["PATH_INFO"]
      end
    end
    registry.config = slow_config

    slow_thread = Thread.new do
      registry.register env.merge("PATH_INFO" => "/slow")
    end
    sleep 0.05
    registry.register env.merge("PATH_INFO" => "/fast")
    slow_thread.join

    paths = registry.snapshot["items"].map { |item| item["path_info"] }
    expect(paths).to include("/fast", "/slow")
  end

  it "rejects on re-entry when reject_new and the registry became full" do
    gate = Mutex.new
    cv = ConditionVariable.new
    state = { open: false }
    registry.config = Puma::Enhanced::Stats::Configuration.new.tap do |configuration|
      configuration.request_limit = 1
      configuration.limit_policy = :reject_new
      configuration.register_fields :request, :gate do |env|
        if env["PATH_INFO"] == "/slow"
          gate.synchronize { cv.wait(gate, 0.5) until state[:open] }
        end
        env["PATH_INFO"]
      end
    end

    slow_result = nil
    slow = Thread.new do
      slow_result = registry.register(env.merge("PATH_INFO" => "/slow"))
    end
    sleep 0.05
    accepted = registry.register(env.merge("PATH_INFO" => "/rejected"))
    gate.synchronize do
      state[:open] = true
      cv.signal
    end
    slow.join

    expect(accepted).not_to be_nil
    expect(slow_result).to be_nil
    snapshot = registry.snapshot
    expect(snapshot["items"].size).to eq(1)
    expect(snapshot["items"].first["path_info"]).to end_with("/rejected")
    expect(snapshot["dropped_count"]).to eq(1)
  end

  describe "started_at" do
    it "uses HTTP_X_REQUEST_START when present" do
      registry.register env.merge("HTTP_X_REQUEST_START" => "t=1718381234.567")

      expect(registry.snapshot["items"].first["started_at"]).to eq(Time.at(1718381234.567).utc.iso8601(6))
    end

    it "parses millisecond timestamps from HTTP_X_REQUEST_START" do
      registry.register env.merge("HTTP_X_REQUEST_START" => "t=1718381234567")

      expect(registry.snapshot["items"].first["started_at"]).to eq(Time.at(1718381234.567).utc.iso8601(6))
    end

    it "parses integer second timestamps from HTTP_X_REQUEST_START" do
      registry.register env.merge("HTTP_X_REQUEST_START" => "t=1718381234")

      expect(registry.snapshot["items"].first["started_at"]).to eq(Time.at(1718381234).utc.iso8601(6))
    end

    it "falls back to the current time when HTTP_X_REQUEST_START is unparseable" do
      freeze_time = Time.utc(2026, 6, 16, 12, 0, 0)
      allow(Time).to receive(:now).and_return(freeze_time)

      registry.register env.merge("HTTP_X_REQUEST_START" => "t=not-a-timestamp")

      expect(registry.snapshot["items"].first["started_at"]).to eq(freeze_time.utc.iso8601(6))
    end

    it "falls back to the current time when HTTP_X_REQUEST_START parsing raises" do
      freeze_time = Time.utc(2026, 6, 16, 12, 0, 0)
      allow(Time).to receive(:now).and_return(freeze_time)
      allow(Time).to receive(:at).and_raise(StandardError)

      registry.register env.merge("HTTP_X_REQUEST_START" => "t=1718381234")

      expect(registry.snapshot["items"].first["started_at"]).to eq(freeze_time.utc.iso8601(6))
    end

    it "falls back to the current time when the header is missing" do
      freeze_time = Time.utc(2026, 6, 16, 12, 0, 0)
      allow(Time).to receive(:now).and_return(freeze_time)

      registry.register env

      expect(registry.snapshot["items"].first["started_at"]).to eq(freeze_time.utc.iso8601(6))
    end
  end

  describe "request id" do
    it "uses action_dispatch.request_id when present" do
      rails_id = "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
      registry.register env.merge("action_dispatch.request_id" => rails_id)

      expect(registry.snapshot["items"].first["id"]).to eq(rails_id)
    end

    it "uses HTTP_X_REQUEST_ID when Rails request id is absent" do
      header_id = "client-supplied-id"
      registry.register env.merge("HTTP_X_REQUEST_ID" => header_id)

      expect(registry.snapshot["items"].first["id"]).to eq(header_id)
    end

    it "prefers action_dispatch.request_id over HTTP_X_REQUEST_ID" do
      registry.register env.merge(
        "action_dispatch.request_id" => "rails-id",
        "HTTP_X_REQUEST_ID" => "client-id"
      )

      expect(registry.snapshot["items"].first["id"]).to eq("rails-id")
    end

    it "falls back to a random id when no request id is available" do
      allow(SecureRandom).to receive(:hex).with(8).and_return("generatedid")

      registry.register env

      expect(registry.snapshot["items"].first["id"]).to eq("generatedid")
    end

    it "ignores blank request ids" do
      allow(SecureRandom).to receive(:hex).with(8).and_return("generatedid")

      registry.register env.merge(
        "action_dispatch.request_id" => "  ",
        "HTTP_X_REQUEST_ID" => ""
      )

      expect(registry.snapshot["items"].first["id"]).to eq("generatedid")
    end
  end

  describe "entry building" do
    let(:full_env) do
      {
        "REQUEST_METHOD" => "GET",
        "PATH_INFO" => "/reports",
        "QUERY_STRING" => "page=2",
        "REQUEST_URI" => "/reports?page=2",
        "REMOTE_ADDR" => "10.0.0.5",
        "rack.session" => { "user_id" => "42" }
      }
    end

    it "builds flat request fields" do
      registry.register full_env
      entry = registry.snapshot["items"].first

      expect(entry).to include(
        "method" => "GET",
        "remote_ip" => "10.0.0.5",
        "path_info" => "/reports"
      )
      expect(entry["started_at"]).not_to be_nil
      expect(entry["id"]).not_to be_nil
    end

    it "maps path_info from SCRIPT_NAME and PATH_INFO without query string" do
      env = {
        "REQUEST_METHOD" => "GET",
        "PATH_INFO" => "/items",
        "QUERY_STRING" => "sort=desc",
        "REQUEST_URI" => "/ignored?sort=desc"
      }

      registry.register env
      expect(registry.snapshot["items"].first["path_info"]).to eq("/items")
    end

    it "prefixes path_info with SCRIPT_NAME when the app is mounted" do
      env = {
        "REQUEST_METHOD" => "GET",
        "SCRIPT_NAME" => "/app",
        "PATH_INFO" => "/items"
      }

      registry.register env
      expect(registry.snapshot["items"].first["path_info"]).to eq("/app/items")
    end

    it "includes session fields on the entry" do
      registry.config = Puma::Enhanced::Stats::Configuration.new.tap do |configuration|
        configuration.register_fields :session, :user_id
      end

      registry.register full_env
      expect(registry.snapshot["items"].first["session"]).to eq("user_id" => "42")
    end

    it "reads request fields from env via []" do
      registry.config = Puma::Enhanced::Stats::Configuration.new.tap do |configuration|
        configuration.register_fields :request, :PATH_INFO
      end

      registry.register full_env
      expect(registry.snapshot["items"].first["PATH_INFO"]).to eq("/reports")
    end

    it "allows request fields to override system defaults" do
      registry.config = Puma::Enhanced::Stats::Configuration.new
      Puma::Enhanced::Stats::DSL::Builder.new(registry.config).instance_eval do
        request :id do |_e|
          "custom-id"
        end
      end

      registry.register full_env
      expect(registry.snapshot["items"].first["id"]).to eq("custom-id")
    end
  end

  describe "field truncation" do
    it "truncates values to max_field_length and marks snapshot truncated" do
      registry.config.max_field_length = 5
      registry.register env.merge("PATH_INFO" => "/very-long-path")

      snapshot = registry.snapshot
      item = snapshot["items"].first
      expect(item["path_info"].bytesize).to be <= 5
      expect(snapshot["truncated"]).to be(true)
    end

    it "resets truncated after snapshot" do
      registry.config.max_field_length = 5
      registry.register env.merge("PATH_INFO" => "/very-long-path")

      expect(registry.snapshot["truncated"]).to be(true)
      expect(registry.snapshot["truncated"]).to be(false)
    end

    it "clears truncated flag on reset" do
      registry.config.max_field_length = 5
      registry.register env.merge("PATH_INFO" => "/very-long-path")
      expect(registry.snapshot["truncated"]).to be(true)

      registry.reset!
      expect(registry.snapshot["truncated"]).to be(false)
    end
  end

  describe "snapshot meta counters" do
    it "resets dropped_count after snapshot" do
      registry.config.limit_policy = :reject_new
      2.times { registry.register(env) }
      registry.register env.merge("PATH_INFO" => "/rejected")

      expect(registry.snapshot["dropped_count"]).to eq(1)
      expect(registry.snapshot["dropped_count"]).to eq(0)
    end
  end

  describe "private eviction helpers" do
    it "no-ops keep_longest eviction when policy is reject_new" do
      registry.config.limit_policy = :reject_new
      2.times { registry.register(env) }

      expect { registry.send(:evict_when_full_keep_longest!) }
        .not_to change { registry.snapshot["items"].size }
    end

    it "no-ops newest eviction when the registry is empty" do
      expect { registry.send(:evict_newest!) }.not_to raise_error
    end
  end
end
