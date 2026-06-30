# frozen_string_literal: true

RSpec.describe Puma::Enhanced::Stats::Snapshot do
  subject(:snapshot) { described_class }

  let(:stats_config) { Puma::Enhanced::Stats::Configuration.new }
  let(:stats_server) { server_double(enhanced_stats: stats_config) }

  def inflight_items(server: stats_server)
    described_class.server(server: server)[:requests]
  end

  let(:env) do
    {
      "REQUEST_METHOD" => "GET",
      "PATH_INFO" => "/",
      "QUERY_STRING" => "",
      "REMOTE_ADDR" => "127.0.0.1",
      "action_dispatch.request_id" => "test-request-id",
      "puma.enhanced_stats.started_at" => Time.utc(2026, 6, 16, 12, 0, 0).utc.iso8601(6)
    }
  end

  it "builds items from inflight envs" do
    with_inflight_env(env) do
      expect(inflight_items.size).to eq(1)
    end
    expect(inflight_items).to be_empty
  end

  it "isolates entries per thread" do
    gate = Mutex.new
    cv = ConditionVariable.new
    state = { registered: 0, release: false }

    threads = %w[/first /second].map.with_index do |path, index|
      Thread.new do
        request_env = env.merge(
          "PATH_INFO" => path,
          "action_dispatch.request_id" => "req-#{index}"
        )
        Thread.current[Puma::Enhanced::Stats::Middleware::KEY] = request_env
        gate.synchronize do
          state[:registered] += 1
          cv.broadcast
          cv.wait(gate, 2) until state[:release]
        end
      ensure
        Thread.current[Puma::Enhanced::Stats::Middleware::KEY] = nil
      end
    end

    gate.synchronize { cv.wait(gate, 2) until state[:registered] == 2 }

    paths = inflight_items.map { |item| item[:path_info] }
    expect(paths).to contain_exactly("/first", "/second")

    gate.synchronize do
      state[:release] = true
      cv.broadcast
    end
    threads.each(&:join)
  end

  it "does not guarantee snapshot item order" do
    gate = Mutex.new
    cv = ConditionVariable.new
    state = { registered: 0, release: false }

    threads = %w[/alpha /beta /gamma].map.with_index do |path, index|
      Thread.new do
        request_env = env.merge(
          "PATH_INFO" => path,
          "action_dispatch.request_id" => "req-#{index}"
        )
        Thread.current[Puma::Enhanced::Stats::Middleware::KEY] = request_env
        gate.synchronize do
          state[:registered] += 1
          cv.broadcast
          cv.wait(gate, 2) until state[:release]
        end
      ensure
        Thread.current[Puma::Enhanced::Stats::Middleware::KEY] = nil
      end
    end

    gate.synchronize { cv.wait(gate, 2) until state[:registered] == 3 }

    expect(inflight_items.map { |item| item[:path_info] }).to match_array(%w[/alpha /beta /gamma])

    gate.synchronize do
      state[:release] = true
      cv.broadcast
    end
    threads.each(&:join)
  end

  it "builds entries while a slow extractor runs on another thread" do
    slow_config = Puma::Enhanced::Stats::Configuration.new.tap do |configuration|
      configuration.register_fields :request, :slow_path do |request_env|
        sleep 0.15 if request_env["PATH_INFO"] == "/slow"
        request_env["PATH_INFO"]
      end
    end

    gate = Mutex.new
    cv = ConditionVariable.new
    state = { release: false }

    slow_thread = Thread.new do
      slow_env = env.merge("PATH_INFO" => "/slow", "action_dispatch.request_id" => "slow-req")
      Thread.current[Puma::Enhanced::Stats::Middleware::KEY] = slow_env
      gate.synchronize do
        cv.wait(gate, 2) until state[:release]
      end
    ensure
      Thread.current[Puma::Enhanced::Stats::Middleware::KEY] = nil
    end

    sleep 0.05
    Thread.current[Puma::Enhanced::Stats::Middleware::KEY] =
      env.merge("PATH_INFO" => "/fast", "action_dispatch.request_id" => "fast-req")
    sleep 0.15

    paths = described_class.server(
      server: server_double(enhanced_stats: slow_config)
    )[:requests].map { |item| item[:path_info] }
    expect(paths).to include("/fast", "/slow")

    gate.synchronize do
      state[:release] = true
      cv.broadcast
    end
    slow_thread.join
  ensure
    Thread.current[Puma::Enhanced::Stats::Middleware::KEY] = nil
  end

  describe "started_at" do
    it "reads the middleware stamp from env" do
      freeze_time = Time.utc(2026, 6, 16, 12, 0, 0)
      stamped = env.merge("puma.enhanced_stats.started_at" => freeze_time.utc.iso8601(6))

      with_inflight_env(stamped) do
        expect(inflight_items.first[:started_at]).to eq(freeze_time.utc.iso8601(6))
      end
    end
  end

  describe "request id" do
    it "uses action_dispatch.request_id as the entry id field" do
      rails_id = "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
      with_inflight_env(env.merge("action_dispatch.request_id" => rails_id)) do
        expect(inflight_items.first[:id]).to eq(rails_id)
      end
    end
  end

  describe "entry building" do
    let(:full_env) do
      env.merge(
        "REQUEST_METHOD" => "GET",
        "PATH_INFO" => "/reports",
        "QUERY_STRING" => "page=2",
        "REQUEST_URI" => "/reports?page=2",
        "REMOTE_ADDR" => "10.0.0.5",
        "action_dispatch.request_id" => "full-env-request-id",
        "rack.session" => { user_id: "42" }
      )
    end

    it "builds flat request fields" do
      with_inflight_env(full_env) do
        entry = inflight_items.first
        expect(entry).to include(
          method: "GET",
          remote_ip: "10.0.0.5",
          path_info: "/reports",
          session: {}
        )
        expect(entry[:started_at]).not_to be_nil
        expect(entry[:id]).not_to be_nil
      end
    end

    it "maps path_info from SCRIPT_NAME and PATH_INFO without query string" do
      request_env = {
        "REQUEST_METHOD" => "GET",
        "PATH_INFO" => "/items",
        "QUERY_STRING" => "sort=desc",
        "REQUEST_URI" => "/ignored?sort=desc",
        "action_dispatch.request_id" => "items-request-id",
        "puma.enhanced_stats.started_at" => Time.now.utc.iso8601(6)
      }

      with_inflight_env(request_env) do
        expect(inflight_items.first[:path_info]).to eq("/items")
      end
    end

    it "includes session fields on the entry" do
      session_config = Puma::Enhanced::Stats::Configuration.new.tap do |configuration|
        configuration.register_fields :session, :user_id
      end

      with_inflight_env(full_env) do
        expect(inflight_items(
          server: server_double(enhanced_stats: session_config)
        ).first[:session]).to eq(user_id: "42")
      end
    end
  end

  describe "field truncation" do
    it "truncates values to max_field_length silently" do
      truncation_config = Puma::Enhanced::Stats::Configuration.new.tap { |c| c.max_field_length = 5 }

      with_inflight_env(env.merge("PATH_INFO" => "/very-long-path")) do
        item = inflight_items(
          server: server_double(enhanced_stats: truncation_config)
        ).first
        expect(item[:path_info]).to eq("/ver…")
        expect(item[:path_info].length).to eq(5)
      end
    end

    it "returns empty registry when extraction raises" do
      failing_config = Puma::Enhanced::Stats::Configuration.new.tap do |configuration|
        configuration.register_fields :request, :boom do |_request_env|
          raise "extractor failed"
        end
      end

      with_inflight_env(env) do
        expect(inflight_items(
          server: server_double(enhanced_stats: failing_config)
        )).to be_empty
      end
    end
  end
end
