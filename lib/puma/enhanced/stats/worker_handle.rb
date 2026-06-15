# frozen_string_literal: true

require "json"

module Puma
  module Enhanced
    module Stats
      # Stores enhanced stats synced from a cluster worker ping payload.
      #
      # The master reads {#enhanced_stats} when building cluster snapshots via
      # {Snapshot}.
      #
      # @see WorkerWrite
      # @see Snapshot
      module WorkerHandle
        # @param idx [Integer] worker index
        # @param pid [Integer] worker process id
        # @param phase [Integer] Puma worker phase
        # @param options [Hash] worker options
        # @return [void]
        def initialize idx, pid, phase, options
          super
          @enhanced_stats = {
            items: [],
            process: nil,
            dropped_count: 0,
            truncated: false,
            synced_at: nil
          }
        end

        # Latest enhanced stats received from the worker ping.
        #
        # @return [Hash{Symbol => Object}] +:items+, +:process+, +:dropped_count+,
        #   +:truncated+, +:synced_at+
        attr_reader :enhanced_stats

        # Parses worker ping JSON and stores +_enhanced_stats+ when present.
        #
        # Delegates to Puma's original implementation when the message is not
        # JSON or parsing fails.
        #
        # @param status [String] raw ping message from the worker
        # @return [void]
        def ping! status
          json_start = status.index "{"
          return super unless json_start

          json = JSON.parse status[json_start..]
          apply_puma_status! json

          payload = Normalizer.fetch(json, :_enhanced_stats)
          if payload
            @enhanced_stats = {
              items: Normalizer.fetch(payload, :items) || [],
              process: Normalizer.fetch(payload, :process),
              dropped_count: Normalizer.fetch(payload, :dropped_count) || 0,
              truncated: Normalizer.fetch(payload, :truncated) || false,
              synced_at: Time.now.utc.iso8601
            }
          end
        rescue JSON::ParserError
          super
        end

        private

        def apply_puma_status! json
          hsh = json.each_with_object({}) do |(key, value), stats|
            next if key == "_enhanced_stats"

            stats[key.to_sym] = value.to_i
          end

          self.class::WORKER_MAX_KEYS.each_with_index do |key, idx|
            next unless hsh[key]

            if hsh[key] < @worker_max[idx]
              hsh[key] = @worker_max[idx]
            else
              @worker_max[idx] = hsh[key]
            end
          end

          @last_checkin = Time.now
          @last_status = hsh
        end
      end
    end
  end
end
