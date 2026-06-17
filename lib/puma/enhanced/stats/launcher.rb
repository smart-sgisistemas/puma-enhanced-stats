# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      # Prepends boot logic onto {Puma::Launcher}.
      #
      # Before calling +super+, assigns +options[:enhanced_stats]+ (or
      # {Configuration.default}) to {CurrentRequests}. In cluster mode, also
      # registers a +before_worker_boot+ hook that calls {CurrentRequests.reset!}
      # so forked workers start with an empty registry.
      #
      # @example Cluster boot sequence
      #   launcher.run
      #   # => CurrentRequests.config = enhanced_config
      #   # => before_worker_boot { CurrentRequests.reset! }
      module Launcher
        # Cluster worker handles for internal snapshot assembly (+nil+ in single mode).
        #
        # Not used by {Puma::Cluster#stats}; keeps +pumactl stats+ in the native Puma format.
        #
        # @return [Array<Puma::Cluster::WorkerHandle>, nil]
        def workers = (@runner.workers if clustered?)

        # Publishes configuration and cluster hooks, then starts Puma.
        #
        # @return [void]
        def run
          enhanced_config = config.options[:enhanced_stats] || Configuration.default

          if clustered?
            config.configure do |_, _, default|
              default.before_worker_boot do
                CurrentRequests.reset!
              end
            end
          end

          CurrentRequests.config = enhanced_config

          super
        end
      end
    end
  end
end
