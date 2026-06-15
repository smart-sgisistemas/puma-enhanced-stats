# frozen_string_literal: true

require "puma/launcher"

RSpec.describe Puma::Enhanced::Stats::Launcher do
  let(:registry) { Puma::Enhanced::Stats::CurrentRequests.instance }

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
    registry.reset!
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

      cluster_hooks = Puma::Enhanced::Stats::PumaCompat.before_worker_boot_hooks cluster_launcher.config
      single_hooks = Puma::Enhanced::Stats::PumaCompat.before_worker_boot_hooks single_launcher.config

      expect(cluster_hooks.length).to eq(1)
      expect(Puma::Enhanced::Stats::PumaCompat.before_worker_boot_cluster_only?(cluster_hooks.first)).to be true
      expect(single_hooks.to_a).to be_empty
    end

    it "clears the registry when the hook runs" do
      registry = Puma::Enhanced::Stats::CurrentRequests.instance
      registry.register(
        "REQUEST_METHOD" => "GET",
        "PATH_INFO" => "/",
        "QUERY_STRING" => "",
        "REMOTE_ADDR" => "127.0.0.1"
      )

      run_with_stubbed_super cluster_launcher
      hook = Puma::Enhanced::Stats::PumaCompat.before_worker_boot_hooks(cluster_launcher.config).first
      Puma::Enhanced::Stats::PumaCompat.before_worker_boot_block(hook).call(0)

      expect(registry.snapshot["items"]).to be_empty
    end
  end

  it "keeps registry config stable across repeated runs" do
    run_with_stubbed_super launcher
    config = registry.config

    run_with_stubbed_super launcher

    expect(registry.config).to equal(config)
  end

  it "assigns registry config from launcher options" do
    custom = Puma::Enhanced::Stats::Configuration.new.tap { |c| c.request_limit = 7 }
    launcher.config.options[:enhanced_stats] = custom

    run_with_stubbed_super launcher

    expect(registry.config).to equal(custom)
  end

  describe "worker_check_interval" do
    let(:cluster_launcher) do
      config = Puma::Configuration.new do |user|
        user.workers 2
        user.worker_check_interval 30
      end
      Puma::Launcher.new(config)
    end

    it "overrides worker_check_interval from sync_interval in cluster mode" do
      cluster_launcher.config.options[:enhanced_stats] =
        Puma::Enhanced::Stats::Configuration.new.tap { |c| c.sync_interval = 8 }

      run_with_stubbed_super cluster_launcher

      expect(cluster_launcher.config.options[:worker_check_interval]).to eq(8)
    end

    it "uses Configuration.default sync_interval when enhanced_stats is omitted" do
      run_with_stubbed_super cluster_launcher

      expect(cluster_launcher.config.options[:worker_check_interval]).to eq(
        Puma::Enhanced::Stats::Configuration.default.sync_interval
      )
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
