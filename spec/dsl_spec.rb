# frozen_string_literal: true

require "puma/configuration"

RSpec.describe Puma::Enhanced::Stats::DSL do
  def build_puma_config &block
    Puma::Configuration.new do |user|
      user.environment "development"
      user.enhanced_stats &block
    end
  end

  def stats_config_from puma_config
    puma_config.instance_variable_get(:@user_dsl)
      .instance_variable_get(:@options)[:enhanced_stats]
  end

  describe "#enhanced_stats" do
    it "stores custom configuration in puma options" do
      puma_config = build_puma_config do
        request :path do |env|
          env["PATH_INFO"]
        end
        request_limit 50
      end

      stats_config = stats_config_from puma_config
      expect(stats_config.request_limit).to eq 50
      expect(stats_config.fields_for(:request).map(&:name)).to include("path")
    end

    it "accepts request_limit, limit_policy, max_field_length, and truncate_suffix" do
      stats_config = stats_config_from(build_puma_config do
        request_limit 50
        limit_policy :reject_new
        max_field_length 512
        truncate_suffix "..."
      end)

      expect(stats_config.request_limit).to eq 50
      expect(stats_config.limit_policy).to eq :reject_new
      expect(stats_config.max_field_length).to eq 512
      expect(stats_config.truncate_suffix).to eq "..."
    end

    it "registers session fields" do
      stats_config = stats_config_from build_puma_config { session :user_id }

      expect(stats_config.fields_for(:session).map(&:name)).to include("user_id")
    end

    it "raises when request_limit is invalid" do
      expect do
        build_puma_config { request_limit 0 }
      end.to raise_error Puma::Enhanced::Stats::Error, /request_limit/
    end

    it "requires a block" do
      expect do
        Puma::Configuration.new do |user|
          user.enhanced_stats
        end
      end.to raise_error ArgumentError, /block required/
    end
  end

  describe Puma::Enhanced::Stats::DSL::Builder do
    it "does not expose configuration readers as zero-argument calls" do
      configuration = Puma::Enhanced::Stats::Configuration.new

      expect do
        described_class.new(configuration).instance_eval { request_limit }
      end.to raise_error ArgumentError, /wrong number of arguments/
    end
  end
end
