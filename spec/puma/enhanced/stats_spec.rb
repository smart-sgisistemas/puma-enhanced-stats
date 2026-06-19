# frozen_string_literal: true

require "puma/configuration"
require "puma/control_cli"
require "puma/launcher"

RSpec.describe Puma::Enhanced::Stats do
  it "has a version number" do
    expect(Puma::Enhanced::Stats::VERSION).to eq("0.4.0")
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

  it "prepends cluster worker and handle modules on load" do
    expect(Puma::Cluster::Worker.ancestors).to include(Puma::Enhanced::Stats::ClusterWorker)
    expect(Puma::Cluster::WorkerHandle.ancestors).to include(Puma::Enhanced::Stats::WorkerHandle)
  end

  it "does not prepend Cluster stats" do
    expect(Puma::Cluster.ancestors.map(&:name)).not_to include("Puma::Enhanced::Stats::Cluster")
  end

  it "registers enhanced-stats in pumactl on load" do
    expect(Puma::ControlCLI::CMD_PATH_SIG_MAP).to include("enhanced-stats")
    expect(Puma::ControlCLI::PRINTABLE_COMMANDS).to include("enhanced-stats")
  end

  it "appends CurrentRequestsMiddleware via Railtie as the innermost layer" do
    middlewares = Rails.application.middleware.map(&:klass)

    expect(middlewares.last).to eq(Puma::Enhanced::Stats::CurrentRequestsMiddleware)
  end
end
