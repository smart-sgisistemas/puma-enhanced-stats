# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      # Publishes +options[:enhanced_stats]+ (or {Configuration.default}) on
      # {CurrentRequests#config=} before {Puma::Launcher#run}.
      #
      # In cluster mode, registers a +before_worker_boot+ hook that clears the
      # registry when a worker process starts, and sets +worker_check_interval+
      # from {Configuration#sync_interval}.
      #
      # @see CurrentRequests
      module Launcher
        # Cluster worker handles from the Puma runner, when clustered.
        #
        # @return [Array<Puma::Cluster::WorkerHandle>, nil]
        def workers = (@runner.workers if clustered?)

        # Assigns registry configuration, applies +worker_check_interval+ from
        # +sync_interval+ when clustered, and starts the Puma launcher.
        #
        # @return [void]
        def run
          enhanced_config = config.options[:enhanced_stats] || Configuration.default

          if clustered?
            config.options[:worker_check_interval] = enhanced_config.sync_interval

            config.configure do |_, _, default|
              default.before_worker_boot do
                CurrentRequests.instance.reset!
              end
            end
          end

          CurrentRequests.instance.config = enhanced_config

          super
        end
      end
    end
  end
end
