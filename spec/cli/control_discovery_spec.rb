# frozen_string_literal: true

require "fileutils"
require "puma/enhanced/stats/cli/control_discovery"

RSpec.describe Puma::Enhanced::Stats::CLI::ControlDiscovery do
  let(:tmpdir) { Dir.mktmpdir("puma-enhanced-stats-discovery-") }

  after do
    FileUtils.remove_entry tmpdir
  end

  def write_config contents, name: "puma.rb"
    path = File.join tmpdir, "config", name
    FileUtils.mkdir_p File.dirname(path)
    File.write path, contents
    path
  end

  def write_state contents
    path = File.join tmpdir, "tmp", "puma.state"
    FileUtils.mkdir_p File.dirname(path)
    File.write path, contents
    path
  end

  it "resolves control_url and token from config/puma.rb" do
    write_config <<~RUBY
      activate_control_app "tcp://127.0.0.1:9393", auth_token: "from-config"
    RUBY

    entry = nil
    Dir.chdir tmpdir do
      entry = described_class.resolve
    end

    expect(entry.control_url).to eq("tcp://127.0.0.1:9393")
    expect(entry.token).to eq("from-config")
  end

  it "prefers config/puma/<environment>.rb over config/puma.rb" do
    write_config "activate_control_app 'http://127.0.0.1:1', auth_token: 'base'"
    write_config "activate_control_app 'http://127.0.0.1:2', auth_token: 'env'", name: "puma/test.rb"

    entry = nil
    Dir.chdir tmpdir do
      entry = described_class.resolve env: { "RAILS_ENV" => "test" }
    end

    expect(entry.control_url).to eq("http://127.0.0.1:2")
    expect(entry.token).to eq("env")
  end

  it "loads state_path from config and prefers the state file for url and token" do
    state_path = write_state <<~STATE
      ---
      control_url: tcp://127.0.0.1:9494
      control_auth_token: from-state
      pid: 4242
    STATE
    write_config <<~RUBY
      state_path "#{state_path.gsub('"', '\\"')}"
      activate_control_app "tcp://127.0.0.1:9393", auth_token: "from-config"
    RUBY

    entry = nil
    Dir.chdir tmpdir do
      entry = described_class.resolve
    end

    expect(entry.state_path).to eq(state_path)
    expect(entry.control_url).to eq("tcp://127.0.0.1:9494")
    expect(entry.token).to eq("from-state")
    expect(entry.master_pid).to eq(4242)
  end

  it "returns empty connection settings when nothing is configured" do
    entry = described_class.resolve env: {}

    expect(entry.control_url).to be_nil
    expect(entry.token).to be_nil
    expect(entry.master_pid).to be_nil
  end

  it "ignores invalid config files" do
    write_config "this is not valid ruby {{"

    entry = nil
    Dir.chdir tmpdir do
      entry = described_class.resolve
    end

    expect(entry.control_url).to be_nil
    expect(entry.token).to be_nil
  end

  it "keeps config defaults when the configured state file is missing" do
    write_config <<~RUBY
      state_path "#{File.join(tmpdir, "missing.state").gsub('"', '\\"')}"
      activate_control_app "tcp://127.0.0.1:9393", auth_token: "from-config"
    RUBY

    entry = nil
    Dir.chdir tmpdir do
      entry = described_class.resolve
    end

    expect(entry.control_url).to eq("tcp://127.0.0.1:9393")
    expect(entry.token).to eq("from-config")
    expect(entry.master_pid).to be_nil
  end
end
