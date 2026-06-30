# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module Single
        EMPTY_POOL_COUNTERS = Puma::Server::STAT_METHODS.to_h { |key| [key, 0] }.freeze

        def enhanced_stats
          return empty_enhanced_stats unless @server

          Snapshot.single(server: @server)
        end

        private

        def empty_enhanced_stats
          {
            collected_at: Time.now.iso8601(6),
            **EMPTY_POOL_COUNTERS,
            requests_in_flight: 0,
            requests: [],
            versions: { :"puma-enhanced-stats" => VERSION }
          }
        end
      end
    end
  end
end
