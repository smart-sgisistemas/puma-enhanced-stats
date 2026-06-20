# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module Launcher
        def workers = (@runner.workers if clustered?)

        def run
          if clustered?
            config.configure do |_, _, default|
              default.before_worker_boot do
                CurrentRequests.reset!
              end
            end
          end

          CurrentRequests.config = config.options[:enhanced_stats] || Configuration.default

          super
        end
      end
    end
  end
end
