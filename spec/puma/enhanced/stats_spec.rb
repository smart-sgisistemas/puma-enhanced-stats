# frozen_string_literal: true

require "puma/configuration"
require "puma/control_cli"
require "puma/launcher"

RSpec.describe Puma::Enhanced::Stats do
  it "has a version number" do
    expect(Puma::Enhanced::Stats::VERSION).to eq("0.5.1")
  end

  it "defines Error" do
    expect(Puma::Enhanced::Stats::Error).to be < StandardError
  end

  it "includes DSL in Puma::DSL" do
    Puma::Configuration.new do |user|
      expect(user).to respond_to :enhanced_stats
    end
  end

  it "prepends DSL on load" do
    expect(Puma::DSL.ancestors).to include(Puma::Enhanced::Stats::DSL)
  end

  it "prepends Launcher on load" do
    expect(Puma::Launcher.ancestors).to include(
      Puma::Enhanced::Stats::Launcher
    )
  end

  it "prepends Cluster on load" do
    expect(Puma::Cluster.ancestors).to include(Puma::Enhanced::Stats::Cluster)
  end

  it "prepends Cluster::Worker on load" do
    expect(Puma::Cluster::Worker.ancestors).to include(Puma::Enhanced::Stats::Worker)
  end

  it "prepends Single on load" do
    expect(Puma::Single.ancestors).to include(Puma::Enhanced::Stats::Single)
  end

  it "prepends WorkerHandle on load" do
    expect(Puma::Cluster::WorkerHandle.ancestors).to include(Puma::Enhanced::Stats::WorkerHandle)
  end

  it "does not prepend removed cluster worker modules" do
    expect(Puma::Cluster::Worker.ancestors.map(&:name)).not_to include("Puma::Enhanced::Stats::ClusterWorker")
  end

  it "registers enhanced-stats in pumactl on load" do
    expect(Puma::ControlCLI::CMD_PATH_SIG_MAP).to include("enhanced-stats")
    expect(Puma::ControlCLI::PRINTABLE_COMMANDS).to include("enhanced-stats")
  end

  it "appends CurrentRequestsMiddleware via Railtie as the innermost layer" do
    middlewares = Rails.application.middleware.map(&:klass)

    expect(middlewares.last).to eq(Puma::Enhanced::Stats::CurrentRequestsMiddleware)
  end

  describe "Puma.enhanced_stats" do
    let(:launcher) { Puma::Launcher.new(Puma::Configuration.new) }

    it "reads enhanced stats from the same stats_object as Puma.stats" do
      runner = launcher.instance_variable_get(:@runner)

      expect(Puma.enhanced_stats_hash).to eq(runner.enhanced_stats)
      expect(Puma.stats_hash).to be_a(Hash)
    end

    it "exposes enhanced_stats_hash and JSON enhanced_stats" do
      hash = Puma.enhanced_stats_hash

      expect(hash[:schema_version]).to eq(1)
      expect(hash[:meta][:mode]).to eq("single")

      json = JSON.parse(Puma.enhanced_stats)
      expect(json["schema_version"]).to eq(1)
    end
  end
end
