# frozen_string_literal: true

require "json"

module Puma
  module Enhanced
    module Stats
      module WorkerHandle
        attr_reader :enhanced_stats

        def initialize(...)
          super(...)
          @enhanced_stats = {
            items: [],
            process: nil,
            dropped_count: 0,
            truncated: false,
            synced_at: nil
          }
        end

        def ping! status
          json = JSON.parse(status.strip, symbolize_names: true)
          store_enhanced_stats! json.delete(:enhanced_stats)
          super(" #{json.map { |key, value| %("#{key}":#{value || 0}) }.join(', ')} }")
        rescue JSON::ParserError
          super
        end

        private

        def store_enhanced_stats! payload
          return unless payload

          @enhanced_stats = {
            items: payload[:items] || [],
            process: payload[:process],
            dropped_count: payload[:dropped_count] || 0,
            truncated: payload[:truncated] || false,
            synced_at: Time.now.utc.iso8601
          }
        end
      end
    end
  end
end
