# frozen_string_literal: true

RSpec.describe Puma::Enhanced::Stats::Configuration do
  subject(:config) { described_class.new }

  it "registers default request fields" do
    names = config.fields_for(:request).map(&:name)
    expect(names).to contain_exactly("method", "remote_ip", "path_info")
  end

  it "validates request_limit and limit_policy in setters" do
    expect { config.request_limit = 0 }.to raise_error Puma::Enhanced::Stats::Error, /request_limit/

    expect { config.limit_policy = :invalid }.to raise_error(
      Puma::Enhanced::Stats::Error,
      "invalid limit_policy invalid (allowed: keep_longest, reject_new)"
    )
  end

  it "validates sync_interval and max_field_length in setters" do
    expect { config.sync_interval = 0 }.to raise_error Puma::Enhanced::Stats::Error, /sync_interval/

    expect { config.max_field_length = 0 }.to raise_error Puma::Enhanced::Stats::Error, /max_field_length/
  end

  it "overrides default request fields with a later definition" do
    expect(config.fields_for(:request).size).to eq 3

    Puma::Enhanced::Stats::DSL::Builder.new(config).instance_eval do
      request :method do |_env|
        "OVERRIDE"
      end
    end

    expect(config.fields_for(:request).size).to eq 3

    env = {
      "REQUEST_METHOD" => "GET",
      "PATH_INFO" => "/",
      "QUERY_STRING" => "",
      "REMOTE_ADDR" => "1.1.1.1"
    }
    registry = Puma::Enhanced::Stats::CurrentRequests.instance
    registry.reset!
    registry.config = config
    registry.register env

    expect(registry.snapshot["items"].first["method"]).to eq "OVERRIDE"
  end

  it "reads request fields from env via [] when no block is given" do
    Puma::Enhanced::Stats::DSL::Builder.new(config).instance_eval do
      request :PATH_INFO
    end

    env = {
      "REQUEST_METHOD" => "GET",
      "PATH_INFO" => "/reports",
      "QUERY_STRING" => "",
      "REMOTE_ADDR" => "1.1.1.1"
    }
    registry = Puma::Enhanced::Stats::CurrentRequests.instance
    registry.reset!
    registry.config = config
    registry.register env

    expect(registry.snapshot["items"].first["PATH_INFO"]).to eq "/reports"
  end

  it "allows custom request fields with a block" do
    config.register_fields :request, :custom do |_env|
      "ok"
    end

    names = config.fields_for(:request).map(&:name)
    expect(names).to include("custom")
  end

  it "registers session fields via register_fields" do
    config.register_fields :session, :user_id

    names = config.fields_for(:session).map(&:name)
    expect(names).to include("user_id")
  end
end
