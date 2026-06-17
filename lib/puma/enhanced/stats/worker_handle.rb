# frozen_string_literal: true

require "json"

module Puma
  module Enhanced
    module Stats
      # Prepends enhanced-stats storage onto {Puma::Cluster::WorkerHandle}.
      #
      # The master stores the latest +enhanced_stats+ payload from each worker
      # ping in {#enhanced_stats}. {Snapshot} reads these handles when building
      # cluster-mode JSON (without mutating {Puma::Cluster#stats}).
      module WorkerHandle
        # Latest enhanced stats received from the worker ping.
        #
        # @return [Hash{Symbol => Object}] +:items+, +:process+, +:dropped_count+,
        #   +:truncated+, +:synced_at+
        attr_reader :enhanced_stats

        # Initializes empty enhanced stats alongside Puma's worker handle state.
        #
        # @return [void]
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

        # Parses worker ping JSON, stores +enhanced_stats+, and delegates
        # standard Puma fields to {Puma::Cluster::WorkerHandle#ping!} without
        # +enhanced_stats+. Falls back to +super+ when the payload is not JSON.
        #
        # @param status [String] raw ping message from the worker
        # @return [void]
        def ping! status
          json = JSON.parse(status.strip, symbolize_names: true)
          store_enhanced_stats! json.delete(:enhanced_stats)
          super(" #{json.map { |key, value| %("#{key}":#{value || 0}) }.join(', ')} }")
        rescue JSON::ParserError
          super
        end

        private

        # Stores a parsed +enhanced_stats+ payload from the worker ping.
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
