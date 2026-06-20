# frozen_string_literal: true

RSpec.describe Puma::Enhanced::Stats::Configuration do
  subject(:config) { described_class.new }

  it "registers default request fields" do
    names = config.fields_for(:request).map(&:name)
    expect(names).to contain_exactly("id", "started_at", "method", "remote_ip", "path_info")
  end

  it "validates request_limit and limit_policy in setters" do
    expect { config.request_limit = 0 }.to raise_error Puma::Enhanced::Stats::Error, /request_limit/

    expect { config.limit_policy = :invalid }.to raise_error(
      Puma::Enhanced::Stats::Error,
      "invalid limit_policy invalid (allowed: keep_longest, reject_new)"
    )
  end

  it "validates max_field_length in setters" do
    expect { config.max_field_length = 0 }.to raise_error Puma::Enhanced::Stats::Error, /max_field_length/
  end

  it "defaults truncate_suffix to the unicode ellipsis" do
    expect(config.truncate_suffix).to eq(Puma::Enhanced::Stats::Configuration::DEFAULT_TRUNCATE_SUFFIX)
    expect(config.truncate_suffix).to eq("…")
  end

  it "accepts nil and empty truncate_suffix" do
    config.truncate_suffix = nil
    expect(config.truncate_suffix).to eq("")

    config.truncate_suffix = ""
    expect(config.truncate_suffix).to eq("")
  end

  it "overrides default request fields with a later definition" do
    expect(config.fields_for(:request).size).to eq 5

    Puma::Enhanced::Stats::DSL::Builder.new(config).instance_eval do
      request :method do |_env|
        "OVERRIDE"
      end
    end

    expect(config.fields_for(:request).size).to eq 5

    env = {
      "REQUEST_METHOD" => "GET",
      "PATH_INFO" => "/",
      "QUERY_STRING" => "",
      "REMOTE_ADDR" => "1.1.1.1",
      "action_dispatch.request_id" => "config-override-request"
    }
    current_requests = Puma::Enhanced::Stats::CurrentRequests
    current_requests.reset!
    current_requests.config = config
    current_requests.register env

    expect(current_requests.snapshot[:items].first[:method]).to eq "OVERRIDE"
  end

  it "reads request fields from env via [] when no block is given" do
    Puma::Enhanced::Stats::DSL::Builder.new(config).instance_eval do
      request :PATH_INFO
    end

    env = {
      "REQUEST_METHOD" => "GET",
      "PATH_INFO" => "/reports",
      "QUERY_STRING" => "",
      "REMOTE_ADDR" => "1.1.1.1",
      "action_dispatch.request_id" => "config-path-info-request"
    }
    current_requests = Puma::Enhanced::Stats::CurrentRequests
    current_requests.reset!
    current_requests.config = config
    current_requests.register env

    expect(current_requests.snapshot[:items].first[:PATH_INFO]).to eq "/reports"
  end

  it "allows custom request fields with a block" do
    config.register_fields :request, :custom do |_env|
      "ok"
    end

    names = config.fields_for(:request).map(&:name)
    expect(names).to include("custom")
  end

  it "requires exactly one name when registering fields with a block" do
    expect do
      config.register_fields :request, :first, :second do |_env|
        "ok"
      end
    end.to raise_error(Puma::Enhanced::Stats::Error, /exactly one name/)
  end

  it "registers session fields via register_fields" do
    config.register_fields :session, :user_id

    names = config.fields_for(:session).map(&:name)
    expect(names).to include("user_id")
  end
end
