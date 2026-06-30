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
        max_field_length 512
      end

      stats_config = stats_config_from puma_config
      expect(stats_config.max_field_length).to eq 512
      expect(stats_config.fields_for(:request).map(&:name)).to include("path")
    end

    it "accepts max_field_length" do
      stats_config = stats_config_from(build_puma_config do
        max_field_length 512
      end)

      expect(stats_config.max_field_length).to eq 512
    end

    it "registers session fields" do
      stats_config = stats_config_from build_puma_config { session :user_id }

      expect(stats_config.fields_for(:session).map(&:name)).to include("user_id")
    end

    it "requires a block" do
      expect do
        Puma::Configuration.new do |user|
          user.enhanced_stats
        end
      end.to raise_error ArgumentError, /block required/
    end
  end
end
