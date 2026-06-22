# frozen_string_literal: true

RSpec.describe Puma::Enhanced::Stats::CurrentRequests do
  subject(:current_requests) { described_class }

  def registry
    current_requests.send(:instance)
  end

  def current_config
    registry.instance_variable_get(:@config)
  end

  let(:env) do
    {
      "REQUEST_METHOD" => "GET",
      "PATH_INFO" => "/",
      "QUERY_STRING" => "",
      "REMOTE_ADDR" => "127.0.0.1",
      "action_dispatch.request_id" => "test-request-id"
    }
  end

  before do
    current_requests.reset!
    current_requests.config = Puma::Enhanced::Stats::Configuration.new.tap do |configuration|
      configuration.request_limit = 2
    end
  end

  it "exposes register and unregister as class methods" do
    described_class.register env
    expect(described_class.snapshot[:items].size).to eq(1)
    described_class.unregister env
    expect(described_class.snapshot[:items]).to be_empty
  end

  it "exposes config= as a class method" do
    custom = Puma::Enhanced::Stats::Configuration.new.tap { |c| c.request_limit = 5 }
    described_class.config = custom
    expect(current_config.request_limit).to eq(5)
  end

  it "registers and unregisters entries" do
    current_requests.register env
    expect(current_requests.snapshot[:items].size).to eq(1)
    current_requests.unregister env
    expect(current_requests.snapshot[:items]).to be_empty
  end

  it "evicts newest entry with keep_longest policy" do
    current_config.limit_policy = :keep_longest

    first_env = env.merge("PATH_INFO" => "/first", "action_dispatch.request_id" => "req-1")
    second_env = env.merge("PATH_INFO" => "/second", "action_dispatch.request_id" => "req-2")
    third_env = env.merge("PATH_INFO" => "/third", "action_dispatch.request_id" => "req-3")

    current_requests.register first_env
    sleep 0.01
    current_requests.register second_env
    sleep 0.01
    current_requests.register third_env

    snapshot = current_requests.snapshot
    paths = snapshot[:items].map { |item| item[:path_info] }
    expect(paths.none? { |path| path.end_with?("/second") })
    expect(snapshot[:dropped_count]).to eq(1)
    expect(paths.any? { |path| path.end_with?("/first") }).to be(true)
    expect(paths.any? { |path| path.end_with?("/third") }).to be(true)
    current_requests.unregister first_env
    current_requests.unregister third_env
  end

  it "rejects new entries when policy is reject_new" do
    current_config.limit_policy = :reject_new

    current_requests.register env.merge("action_dispatch.request_id" => "req-1")
    current_requests.register env.merge("action_dispatch.request_id" => "req-2")
    current_requests.register env.merge("PATH_INFO" => "/rejected", "action_dispatch.request_id" => "req-3")

    snapshot = current_requests.snapshot
    expect(snapshot[:items].size).to eq(2)
    expect(snapshot[:dropped_count]).to eq(1)
  end

  it "overwrites duplicate request ids" do
    shared_id = "same-request-id"
    current_requests.register env.merge("action_dispatch.request_id" => shared_id, "PATH_INFO" => "/first")
    current_requests.register env.merge("action_dispatch.request_id" => shared_id, "PATH_INFO" => "/second")

    snapshot = current_requests.snapshot
    expect(snapshot[:items].size).to eq(1)
    expect(snapshot[:items].first[:path_info]).to end_with("/second")
    expect(snapshot[:dropped_count]).to eq(0)
  end

  it "registers another request while a slow extractor runs" do
    slow_config = Puma::Enhanced::Stats::Configuration.new.tap do |configuration|
      configuration.request_limit = 10
      configuration.register_fields :request, :slow_path do |env|
        sleep 0.15 if env["PATH_INFO"] == "/slow"
        env["PATH_INFO"]
      end
    end
    current_requests.config = slow_config

    slow_thread = Thread.new do
      current_requests.register env.merge("PATH_INFO" => "/slow", "action_dispatch.request_id" => "slow-req")
    end
    sleep 0.05
    current_requests.register env.merge("PATH_INFO" => "/fast", "action_dispatch.request_id" => "fast-req")
    slow_thread.join

    paths = current_requests.snapshot[:items].map { |item| item[:path_info] }
    expect(paths).to include("/fast", "/slow")
  end

  it "rejects on re-entry when reject_new and the registry became full" do
    gate = Mutex.new
    cv = ConditionVariable.new
    state = { open: false }
    current_requests.config = Puma::Enhanced::Stats::Configuration.new.tap do |configuration|
      configuration.request_limit = 1
      configuration.limit_policy = :reject_new
      configuration.register_fields :request, :gate do |env|
        if env["PATH_INFO"] == "/slow"
          gate.synchronize { cv.wait(gate, 0.5) until state[:open] }
        end
        env["PATH_INFO"]
      end
    end

    slow = Thread.new do
      current_requests.register env.merge("PATH_INFO" => "/slow", "action_dispatch.request_id" => "slow-req")
    end
    sleep 0.05
    current_requests.register env.merge("PATH_INFO" => "/rejected", "action_dispatch.request_id" => "accepted-req")
    gate.synchronize do
      state[:open] = true
      cv.signal
    end
    slow.join

    snapshot = current_requests.snapshot
    expect(snapshot[:items].size).to eq(1)
    expect(snapshot[:items].first[:path_info]).to end_with("/rejected")
    expect(snapshot[:dropped_count]).to eq(1)
  end

  describe "started_at" do
    it "uses the current UTC time" do
      freeze_time = Time.utc(2026, 6, 16, 12, 0, 0)
      allow(Time).to receive(:now).and_return(freeze_time)

      current_requests.register env

      expect(current_requests.snapshot[:items].first[:started_at]).to eq(freeze_time.utc.iso8601(6))
    end
  end

  describe "request id" do
    it "uses action_dispatch.request_id as the entry key" do
      rails_id = "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
      current_requests.register env.merge("action_dispatch.request_id" => rails_id)

      expect(current_requests.snapshot[:items].first[:id]).to eq(rails_id)
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
        "action_dispatch.request_id" => "full-env-request-id",
        "rack.session" => { user_id: "42" }
      }
    end

    it "builds flat request fields" do
      current_requests.register full_env
      entry = current_requests.snapshot[:items].first

      expect(entry).to include(
        method: "GET",
        remote_ip: "10.0.0.5",
        path_info: "/reports",
        session: {}
      )
      expect(entry[:started_at]).not_to be_nil
      expect(entry[:id]).not_to be_nil
    end

    it "maps path_info from SCRIPT_NAME and PATH_INFO without query string" do
      env = {
        "REQUEST_METHOD" => "GET",
        "PATH_INFO" => "/items",
        "QUERY_STRING" => "sort=desc",
        "REQUEST_URI" => "/ignored?sort=desc",
        "action_dispatch.request_id" => "items-request-id"
      }

      current_requests.register env
      expect(current_requests.snapshot[:items].first[:path_info]).to eq("/items")
    end

    it "prefixes path_info with SCRIPT_NAME when the app is mounted" do
      env = {
        "REQUEST_METHOD" => "GET",
        "SCRIPT_NAME" => "/app",
        "PATH_INFO" => "/items",
        "action_dispatch.request_id" => "mounted-request-id"
      }

      current_requests.register env
      expect(current_requests.snapshot[:items].first[:path_info]).to eq("/app/items")
    end

    it "includes session fields on the entry" do
      current_requests.config = Puma::Enhanced::Stats::Configuration.new.tap do |configuration|
        configuration.register_fields :session, :user_id
      end

      current_requests.register full_env
      expect(current_requests.snapshot[:items].first[:session]).to eq(user_id: "42")
    end

    it "reads request fields from env via []" do
      current_requests.config = Puma::Enhanced::Stats::Configuration.new.tap do |configuration|
        configuration.register_fields :request, :PATH_INFO
      end

      current_requests.register full_env
      expect(current_requests.snapshot[:items].first[:PATH_INFO]).to eq("/reports")
    end

    it "allows request fields to override system defaults" do
      current_requests.config = Puma::Enhanced::Stats::Configuration.new
      Puma::Enhanced::Stats::DSL::Builder.new(current_config).instance_eval do
        request :id do |_e|
          "custom-id"
        end
      end

      current_requests.register full_env
      expect(current_requests.snapshot[:items].first[:id]).to eq("custom-id")
    end
  end

  describe "field truncation" do
    it "truncates values to max_field_length and marks snapshot truncated" do
      current_config.max_field_length = 5
      current_requests.register env.merge("PATH_INFO" => "/very-long-path")

      snapshot = current_requests.snapshot
      item = snapshot[:items].first
      expect(item[:path_info]).to eq("/ver…")
      expect(item[:path_info].length).to eq(5)
      expect(snapshot[:truncated]).to be(true)
    end

    it "truncates multibyte strings by character length" do
      current_config.max_field_length = 3
      current_requests.register env.merge("PATH_INFO" => "café-long")

      item = current_requests.snapshot[:items].first
      expect(item[:path_info]).to eq("ca…")
      expect(item[:path_info].valid_encoding?).to be(true)
    end

    it "always appends the suffix, even at the minimum field length" do
      current_config.max_field_length = 1
      current_requests.register env.merge("PATH_INFO" => "abcdef")

      expect(current_requests.snapshot[:items].first[:path_info]).to eq("…")
    end

    it "truncates without a suffix when truncate_suffix is empty" do
      current_config.max_field_length = 5
      current_config.truncate_suffix = ""
      current_requests.register env.merge("PATH_INFO" => "/very-long-path")

      expect(current_requests.snapshot[:items].first[:path_info]).to eq("/very")
    end

    it "resets truncated after snapshot" do
      current_config.max_field_length = 5
      current_requests.register env.merge("PATH_INFO" => "/very-long-path")

      expect(current_requests.snapshot[:truncated]).to be(true)
      expect(current_requests.snapshot[:truncated]).to be(false)
    end

    it "clears truncated flag on reset" do
      current_config.max_field_length = 5
      current_requests.register env.merge("PATH_INFO" => "/very-long-path")
      expect(current_requests.snapshot[:truncated]).to be(true)

      current_requests.reset!
      expect(current_requests.snapshot[:truncated]).to be(false)
    end
  end

  describe "registration resilience" do
    it "does not register when field extraction raises" do
      current_requests.config = Puma::Enhanced::Stats::Configuration.new.tap do |configuration|
        configuration.register_fields :request, :boom do |_env|
          raise "extractor failed"
        end
      end

      current_requests.register env

      expect(current_requests.snapshot[:items]).to be_empty
    end

    it "allows repeated unregister of the same request" do
      current_requests.register env

      current_requests.unregister env
      current_requests.unregister env

      expect(current_requests.snapshot[:items]).to be_empty
    end

    it "allows unregister when the request was not registered" do
      expect { current_requests.unregister env.merge("action_dispatch.request_id" => "missing-request") }.not_to raise_error
    end

    it "does not raise when unregister fails internally" do
      current_requests.register env
      allow(registry.instance_variable_get(:@mutex)).to receive(:synchronize).and_raise(StandardError)

      expect { current_requests.unregister(env) }.not_to raise_error
    end
  end

  describe "snapshot meta counters" do
    it "resets dropped_count after snapshot" do
      current_config.limit_policy = :reject_new
      current_requests.register env.merge("action_dispatch.request_id" => "req-1")
      current_requests.register env.merge("action_dispatch.request_id" => "req-2")
      current_requests.register env.merge("PATH_INFO" => "/rejected", "action_dispatch.request_id" => "req-3")

      expect(current_requests.snapshot[:dropped_count]).to eq(1)
      expect(current_requests.snapshot[:dropped_count]).to eq(0)
    end
  end

  describe "private eviction helpers" do
    it "rejects instead of evicting when policy is reject_new" do
      current_config.limit_policy = :reject_new
      current_requests.register env.merge("action_dispatch.request_id" => "req-1")
      current_requests.register env.merge("action_dispatch.request_id" => "req-2")

      expect(current_requests.snapshot[:items].size).to eq(2)

      current_requests.register env.merge("action_dispatch.request_id" => "req-3")

      snapshot = current_requests.snapshot
      expect(snapshot[:items].size).to eq(2)
      expect(snapshot[:dropped_count]).to eq(1)
    end

    it "no-ops when the registry is not full" do
      expect(registry.send(:full?)).to be(false)
      expect { registry.send(:evict_newest!) }.not_to change { registry.snapshot[:items].size }
    end

    it "returns early when evict_newest! runs on an empty registry" do
      expect { registry.send(:evict_newest!) }.not_to raise_error
    end

    it "evicts during the post-build registration check when full" do
      gate = Mutex.new
      cv = ConditionVariable.new
      state = { open: false }
      current_requests.config = Puma::Enhanced::Stats::Configuration.new.tap do |configuration|
        configuration.request_limit = 1
        configuration.limit_policy = :keep_longest
        configuration.register_fields :request, :gate do |env|
          if env["PATH_INFO"] == "/slow"
            gate.synchronize { cv.wait(gate, 0.5) until state[:open] }
          end
          env["PATH_INFO"]
        end
      end

      slow = Thread.new do
        current_requests.register env.merge("PATH_INFO" => "/slow", "action_dispatch.request_id" => "slow-req")
      end
      sleep 0.05
      current_requests.register env.merge("PATH_INFO" => "/fast", "action_dispatch.request_id" => "fast-req")
      gate.synchronize do
        state[:open] = true
        cv.signal
      end
      slow.join

      snapshot = current_requests.snapshot
      expect(snapshot[:items].size).to eq(1)
      expect(snapshot[:items].first[:path_info]).to end_with("/slow")
      expect(snapshot[:dropped_count]).to eq(1)
    end
  end
end
