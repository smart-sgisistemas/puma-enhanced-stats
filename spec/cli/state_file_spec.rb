# frozen_string_literal: true

require "puma/enhanced/stats/cli/state_file"

RSpec.describe Puma::Enhanced::Stats::CLI::StateFile do
  let(:path) { File.join(Dir.tmpdir, "puma-enhanced-stats-state-#{Process.pid}.yml") }

  after do
    File.delete(path) if File.exist?(path)
  end

  it "returns nil for a missing file" do
    expect(described_class.load("/tmp/puma-enhanced-stats-missing-#{Process.pid}")).to be_nil
  end

  it "reads control_url, token, and pid via Puma::StateFile" do
    stub_const("Puma::StateFile", Class.new)
    state = instance_double(
      "Puma::StateFile",
      control_url: "http://127.0.0.1:9393",
      control_options: { auth_token: "puma-token" },
      pid: 4242
    )
    allow(Puma::StateFile).to receive(:new).with(path).and_return(state)
    File.write path, "ignored: true\n"

    entry = described_class.load(path)

    expect(entry.control_url).to eq("http://127.0.0.1:9393")
    expect(entry.token).to eq("puma-token")
    expect(entry.master_pid).to eq(4242)
  end

  it "reads string-keyed auth tokens from Puma::StateFile" do
    stub_const("Puma::StateFile", Class.new)
    state = instance_double(
      "Puma::StateFile",
      control_url: "http://127.0.0.1:9393",
      control_options: { "auth_token" => "string-token" },
      pid: 55
    )
    allow(Puma::StateFile).to receive(:new).with(path).and_return(state)
    File.write path, "ignored: true\n"

    entry = described_class.load(path)

    expect(entry.token).to eq("string-token")
  end

  it "reads control_url when control_options are absent" do
    stub_const("Puma::StateFile", Class.new)
    state = instance_double(
      "Puma::StateFile",
      control_url: "http://127.0.0.1:9393",
      control_options: nil,
      pid: 55
    )
    allow(Puma::StateFile).to receive(:new).with(path).and_return(state)
    File.write path, "ignored: true\n"

    entry = described_class.load(path)

    expect(entry.control_url).to eq("http://127.0.0.1:9393")
    expect(entry.token).to be_nil
  end

  it "reads control_url, token, and pid from YAML" do
    File.write path, <<~YAML
      pid: 4242
      control_url: tcp://127.0.0.1:9293
      control_options:
        auth_token: secret
    YAML

    entry = described_class.load(path)

    expect(entry.control_url).to eq("tcp://127.0.0.1:9293")
    expect(entry.token).to eq("secret")
    expect(entry.master_pid).to eq(4242)
  end

  it "falls back to YAML when Puma::StateFile raises" do
    stub_const("Puma::StateFile", Class.new do
      def initialize(*) = raise StandardError, "broken"
    end)
    File.write path, <<~YAML
      pid: 99
      control_url: http://127.0.0.1:9293
      control_options:
        auth_token: yaml-token
    YAML

    entry = described_class.load(path)

    expect(entry.token).to eq("yaml-token")
    expect(entry.master_pid).to eq(99)
  end

  it "returns nil when YAML cannot be parsed" do
    File.write path, ": invalid: yaml: ["

    expect(described_class.load(path)).to be_nil
  end
end
