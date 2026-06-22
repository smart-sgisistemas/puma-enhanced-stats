# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module WorkerHandle
        EMPTY_ENHANCED_STATS = {
          items: [],
          dropped_count: 0,
          truncated: false,
          synced_at: nil
        }.merge(Puma::Server::STAT_METHODS.to_h { |key| [key, 0] }).freeze

        def initialize *args
          @last_enhanced_stats = EMPTY_ENHANCED_STATS.dup
          super
        end

        attr_reader :last_enhanced_stats

        def enhanced_ping! snapshot
          @last_enhanced_stats = {
            items: snapshot[:items] || [],
            dropped_count: snapshot[:dropped_count] || 0,
            truncated: snapshot[:truncated] || false,
            synced_at: Time.now.utc.iso8601
          }.merge(Puma::Server::STAT_METHODS.to_h { |key| [key, snapshot[key] || 0] })
        rescue StandardError
          nil
        end
      end
    end
  end
end
