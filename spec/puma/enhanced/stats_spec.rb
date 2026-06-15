# frozen_string_literal: true

require "puma/configuration"
require "puma/control_cli"
require "puma/launcher"

RSpec.describe Puma::Enhanced::Stats do
  it "has a version number" do
    expect(Puma::Enhanced::Stats::VERSION).to eq("0.1.1")
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

  it "registers enhanced-stats in pumactl on load" do
    expect(Puma::ControlCLI::CMD_PATH_SIG_MAP).to include("enhanced-stats")
    expect(Puma::ControlCLI::PRINTABLE_COMMANDS).to include("enhanced-stats")
  end

  it "inserts middleware via Railtie after the session store" do
    session_klass = ActionDispatch::Session.resolve_store(Rails.application.config.session_store)
    middlewares = Rails.application.middleware.map(&:klass)
    session_index = middlewares.index(session_klass)
    stats_index = middlewares.index(Puma::Enhanced::Stats::Middleware)

    expect(stats_index).to be > session_index
  end
end
