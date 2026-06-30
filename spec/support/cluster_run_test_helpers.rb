# frozen_string_literal: true

module ClusterRunTestHelpers
  NATIVE_CLUSTER_RUN = begin
    config = Puma::Configuration.new { |c| c.workers 1 }
    runner = Puma::Launcher.new(config).instance_variable_get(:@runner)
    runner.method(:run).super_method.unbind
  end

  NATIVE_CLUSTER_WORKER = begin
    config = Puma::Configuration.new { |c| c.workers 1 }
    runner = Puma::Launcher.new(config).instance_variable_get(:@runner)
    runner.method(:worker).super_method.unbind
  end

  module_function

  def stub_cluster_super_run!(wait: 0.5)
    Puma::Cluster.class_eval do
      define_method(:__stats_test_cluster_run_stub) { sleep wait }
      remove_method :run if instance_methods(false).include?(:run)
      alias_method :run, :__stats_test_cluster_run_stub
    end
  end

  def restore_cluster_super_run!
    native_run = NATIVE_CLUSTER_RUN
    Puma::Cluster.class_eval do
      remove_method :run if instance_methods(false).include?(:run)
      remove_method :__stats_test_cluster_run_stub if method_defined?(:__stats_test_cluster_run_stub, false)
      remove_method :__stats_test_original_cluster_run if method_defined?(:__stats_test_original_cluster_run, false)

      define_method(:run) { native_run.bind(self).call }
    end
  end

  def stub_cluster_super_worker!
    Puma::Cluster.class_eval do
      define_method(:__stats_test_cluster_worker_stub) { |*| }
      remove_method :worker if instance_methods(false).include?(:worker)
      alias_method :worker, :__stats_test_cluster_worker_stub
    end
  end

  def restore_cluster_super_worker!
    native_worker = NATIVE_CLUSTER_WORKER
    Puma::Cluster.class_eval do
      remove_method :worker if instance_methods(false).include?(:worker)
      remove_method :__stats_test_cluster_worker_stub if method_defined?(:__stats_test_cluster_worker_stub, false)
      remove_method :__stats_test_original_worker if method_defined?(:__stats_test_original_worker, false)

      define_method(:worker) { |*args| native_worker.bind(self).call(*args) }
    end
  end
end

RSpec.configure do |config|
  config.include ClusterRunTestHelpers

  config.before(:each, :integration) do
    ClusterRunTestHelpers.restore_cluster_super_run!
    ClusterRunTestHelpers.restore_cluster_super_worker!
  end
end
