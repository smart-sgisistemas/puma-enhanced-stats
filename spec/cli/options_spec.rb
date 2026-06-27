# frozen_string_literal: true

require "puma/enhanced/stats/cli/options"

RSpec.describe Puma::Enhanced::Stats::CLI::Options do
  subject(:options) { described_class.new }

  it "defaults to watch mode with stacked layout" do
    expect(options.watch?).to be true
    expect(options.frame_layout).to eq "stacked"
    expect(options.request_display).to eq "auto"
    expect(options.sort_process).to eq "severity"
  end

  it "shows TOP and PROCESSES by default" do
    expect(options.top?).to be true
  end

  it "hides TOP and PROCESSES when --no-top is set" do
    options.no_top = true
    expect(options.top?).to be false
  end

  it "respects show_top from user config" do
    options.show_top = "false"
    expect(options.top?).to be false
    expect(options.show_top?).to be false
  end

  it "builds connection overrides from CLI flags" do
    options.state_path = "/tmp/puma.state"
    options.control_url = "tcp://127.0.0.1:9293"
    options.token = "secret"
    options.config_path = "config/puma.rb"

    expect(options.connection_overrides).to eq(
      state_path: "/tmp/puma.state",
      control_url: "tcp://127.0.0.1:9293",
      token: "secret",
      config_path: "config/puma.rb"
    )
  end

  it "omits blank connection overrides" do
    options.control_url = ""
    options.token = nil

    expect(options.connection_overrides).to eq({})
  end
end
