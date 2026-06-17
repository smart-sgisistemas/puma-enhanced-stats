# frozen_string_literal: true

require "json"

module Puma
  module Enhanced
    module Stats
      # Prepends enhanced-stats storage onto {Puma::Cluster::WorkerHandle}.
      #
      # The master stores the latest +_enhanced_stats+ payload from each worker
      # ping in {#enhanced_stats}. {Snapshot} reads these handles when building
      # cluster-mode JSON.
      module WorkerHandle
        # Latest enhanced stats received from the worker ping.
        #
        # @return [Hash{Symbol => Object}] +:items+, +:process+, +:dropped_count+,
        #   +:truncated+, +:synced_at+
        attr_reader :enhanced_stats

        # Initializes empty enhanced stats alongside Puma's worker handle state.
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

        # Parses worker ping JSON and stores +_enhanced_stats+ when present.
        #
        # Also updates Puma's standard worker status via {#apply_puma_status!}.
        # Delegates to Puma's original implementation when the message is not JSON.
        #
        # @param status [String] raw ping message from the worker
        def ping! status
          json_start = status.index "{"
          return super unless json_start

          json = JSON.parse status[json_start..]
          apply_puma_status! json

          payload = Snapshot.fetch(json, :_enhanced_stats)
          if payload
            @enhanced_stats = {
              items: Snapshot.fetch(payload, :items) || [],
              process: Snapshot.fetch(payload, :process),
              dropped_count: Snapshot.fetch(payload, :dropped_count) || 0,
              truncated: Snapshot.fetch(payload, :truncated) || false,
              synced_at: Time.now.utc.iso8601
            }
          end
        rescue JSON::ParserError
          nil
        end

        private

        # Updates Puma worker status from ping JSON, excluding +_enhanced_stats+.
        #
        # Mirrors Puma's max-tracking logic for backlog, running, etc.
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
