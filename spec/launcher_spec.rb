# frozen_string_literal: true

require "puma/launcher"

RSpec.describe Puma::Enhanced::Stats::Launcher do
  let(:current_requests) { Puma::Enhanced::Stats::CurrentRequests }

  let(:launcher) do
    config = Puma::Configuration.new do |user|
      user.environment "development"
    end
    Puma::Launcher.new(config)
  end

  def run_with_stubbed_super launcher_instance
    Puma::Launcher.class_eval do
      alias_method :__stats_test_original_run, :run unless method_defined?(:__stats_test_original_run, false)

      def run
        :ran
      end
    end

    described_class
      .instance_method(:run)
      .bind(launcher_instance)
      .call
  ensure
    Puma::Launcher.class_eval do
      alias_method :run, :__stats_test_original_run
      remove_method :__stats_test_original_run
    end
  end

  before do
    current_requests.reset!
  end

  def before_worker_boot_hooks config
    config.options.default_options[:before_worker_boot] || []
  end

  describe "before_worker_boot" do
    let(:cluster_launcher) do
      config = Puma::Configuration.new do |user|
        user.workers 2
      end
      Puma::Launcher.new(config)
    end

    let(:single_launcher) do
      Puma::Launcher.new(Puma::Configuration.new)
    end

    it "registers the hook only in cluster mode" do
      run_with_stubbed_super cluster_launcher
      run_with_stubbed_super single_launcher

      cluster_hooks = before_worker_boot_hooks cluster_launcher.config
      single_hooks = before_worker_boot_hooks single_launcher.config

      expect(cluster_hooks.length).to eq(1)
      expect(cluster_hooks.first[:cluster_only]).to be true
      expect(single_hooks.to_a).to be_empty
    end

    it "clears the registry when the hook runs" do
      current_requests.register(
        "REQUEST_METHOD" => "GET",
        "PATH_INFO" => "/",
        "QUERY_STRING" => "",
        "REMOTE_ADDR" => "127.0.0.1",
        "action_dispatch.request_id" => "launcher-hook-request"
      )

      run_with_stubbed_super cluster_launcher
      hook = before_worker_boot_hooks(cluster_launcher.config).first
      hook[:block].call(0)

      expect(current_requests.snapshot["items"]).to be_empty
    end
  end

  it "keeps current_requests config stable across repeated runs" do
    run_with_stubbed_super launcher
    config = current_requests.send(:instance).instance_variable_get(:@config)

    run_with_stubbed_super launcher

    expect(current_requests.send(:instance).instance_variable_get(:@config)).to equal(config)
  end

  it "assigns current_requests config from launcher options" do
    custom = Puma::Enhanced::Stats::Configuration.new.tap { |c| c.request_limit = 7 }
    launcher.config.options[:enhanced_stats] = custom

    run_with_stubbed_super launcher

    expect(current_requests.send(:instance).instance_variable_get(:@config)).to equal(custom)
  end

  it "returns nil workers in single mode" do
    single = Puma::Launcher.new(Puma::Configuration.new)

    expect(single.workers).to be_nil
  end

  describe "worker_check_interval" do
    let(:cluster_launcher) do
      config = Puma::Configuration.new do |user|
        user.workers 2
        user.worker_check_interval 30
      end
      Puma::Launcher.new(config)
    end

    it "does not override worker_check_interval in cluster mode" do
      run_with_stubbed_super cluster_launcher

      expect(cluster_launcher.config.options[:worker_check_interval]).to eq(30)
    end

    it "does not override worker_check_interval in single mode" do
      config = Puma::Configuration.new do |user|
        user.worker_check_interval 30
      end
      single_launcher = Puma::Launcher.new(config)

      run_with_stubbed_super single_launcher

      expect(single_launcher.config.options[:worker_check_interval]).to eq(30)
    end
  end
end
