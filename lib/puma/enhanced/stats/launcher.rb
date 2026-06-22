# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module Launcher
        def runner
          @runner
        end

        def run
          CurrentRequests.config = config.options[:enhanced_stats] || Configuration.default
          super
        end

        def enhanced_stats
          @runner.enhanced_stats
        end
      end
    end
  end
end
