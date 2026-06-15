# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      # Normalizes raw worker and request data for the public JSON contract.
      #
      # Used by {Snapshot} when assembling worker entries and summary counters.
      #
      # @see Snapshot.build
      module Normalizer
        module_function

        # Reads +key+ from +hash+ whether stored as a symbol or string.
        #
        # @param hash [Hash, nil]
        # @param key [Symbol, String]
        # @return [Object, nil]
        def fetch hash, key
          return nil if hash.nil?

          hash[key] || hash[key.to_s] || hash[key.to_sym]
        end

        # Adds +elapsed_ms+ to an in-flight item from +started_at+.
        #
        # @param item [Hash{String => Object}]
        # @param now [Time]
        # @return [Hash{String => Object}]
        def item_with_elapsed item, now
          started = Time.iso8601 item["started_at"]
          item.merge "elapsed_ms" => ((now - started) * 1000).to_i
        rescue ArgumentError
          item.merge "elapsed_ms" => nil
        end

        # Normalizes process metrics to string keys for the public contract.
        #
        # @param raw [Hash, nil]
        # @return [Hash{String => Integer, Float, nil}]
        def normalize_process raw
          return ProcessMetrics::EMPTY if raw.nil?

          {
            "rss_bytes" => fetch(raw, :rss_bytes),
            "cpu_percent" => fetch(raw, :cpu_percent)
          }
        end

        # Builds the +requests+ section for a worker entry.
        #
        # @param items [Array<Hash>]
        # @param config [Configuration]
        # @param truncated [Boolean]
        # @param dropped_count [Integer]
        # @return [Hash{String => Object}]
        def requests_section items:, config:, truncated:, dropped_count:
          {
            "meta" => {
              "count" => items.size,
              "request_limit" => config.request_limit,
              "limit_policy" => config.limit_policy.to_s,
              "truncated" => truncated,
              "dropped_count" => dropped_count
            },
            "items" => items
          }
        end

        # Picks standard Puma thread-pool keys from a worker status hash.
        #
        # @param last_status [Hash, nil]
        # @return [Hash{String => Integer}]
        def pick_puma_stats last_status
          {
            "backlog" => fetch(last_status, :backlog) || 0,
            "running" => fetch(last_status, :running) || 0,
            "pool_capacity" => fetch(last_status, :pool_capacity) || 0,
            "max_threads" => fetch(last_status, :max_threads) || 0,
            "requests_count" => fetch(last_status, :requests_count) || 0
          }
        end

        # Aggregates cluster-wide request counters.
        #
        # @param workers [Array<Hash>]
        # @return [Hash{String => Integer}]
        def summary workers
          {
            "workers_total" => workers.size,
            "workers_reporting" => workers.count { |worker| worker["synced_at"] },
            "requests_in_flight" => workers.sum { |w| w.dig("requests", "meta", "count") || 0 },
            "requests_dropped_total" => workers.sum { |w| w.dig("requests", "meta", "dropped_count") || 0 }
          }
        end
      end
    end
  end
end
