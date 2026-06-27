# frozen_string_literal: true

require "puma/enhanced/stats/cli"

RSpec.describe Puma::Enhanced::Stats::CLI do
  it "loads packaging and infra modules without requiring Rails boot path" do
    expect(described_class).to be_a Module
    expect(Puma::Enhanced::Stats::CLI::Options).to be_a Class
    expect(Puma::Enhanced::Stats::CLI::UserConfig).to be_a Class
    expect(Puma::Enhanced::Stats::CLI::ControlDiscovery).to be_a Class
    expect(Puma::Enhanced::Stats::CLI::StateFile).to be_a Class
    expect(Puma::Enhanced::Stats::CLI::Fetcher).to be_a Class
    expect(Puma::Enhanced::Stats::CLI::Runner).to be_a Class
  end

  it "does not load CLI from the main gem entry point" do
    source = File.read(File.expand_path("../../lib/puma/enhanced/stats.rb", __dir__))
    expect(source).not_to include('require_relative "cli"')
    expect(source).not_to match(/enhanced\/stats\/cli/)
  end
end
