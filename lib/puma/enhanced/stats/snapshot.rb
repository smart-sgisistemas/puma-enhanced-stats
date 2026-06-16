# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      # Builds the public enhanced-stats JSON document (schema v1).
      #
      # Used by {Status} and +pumactl enhanced-stats+.
      #
      # In single mode, reads the live {CurrentRequests} and
      # {ProcessMetrics.read}. In cluster mode, merges data synced from workers
      # via {WorkerHandle}. Limits and field extractors come from
      # +launcher.config.options[:enhanced_stats]+ or {Configuration.default}.
      #
      # @see Configuration.default
      # @see schema/enhanced-stats-v1.json
      class Snapshot
        class << self
          # Builds the enhanced-stats JSON document (schema v1).
          #
          # @param launcher [Puma::Launcher]
          # @return [Hash{String => Object}] payload matching schema v1
          # @see schema/enhanced-stats-v1.json
          def build launcher
            now = Time.now.utc
            config = config_for launcher
            stats = launcher_stats launcher
            workers = normalize_workers launcher, now, config, stats

            {
              "schema_version" => 1,
              "meta" => meta(stats, now, config),
              "summary" => summary(workers),
              "workers" => workers
            }
          end

          # Reads +key+ from +hash+ whether stored as a symbol or string.
          #
          # @param hash [Hash, nil]
          # @param key [Symbol, String]
          # @return [Object, nil]
          def fetch hash, key
            return nil if hash.nil?

            hash[key] || hash[key.to_s] || hash[key.to_sym]
          end

          private

          def config_for(launcher) = launcher.config.options[:enhanced_stats] || Configuration.default

          def launcher_stats launcher
            if launcher.respond_to? :stats
              launcher.stats
            elsif launcher.respond_to? :stats_hash
              launcher.stats_hash
            else
              {}
            end
          end

          def meta stats, now, config
            {
              "collected_at" => now.iso8601,
              "gem_version" => VERSION,
              "puma_version" => Puma::Const::PUMA_VERSION,
              "ruby_version" => RUBY_VERSION,
              "mode" => cluster?(stats) ? "cluster" : "single",
              "sync_interval_seconds" => config.sync_interval
            }
          end

          def cluster?(stats) = fetch(stats, :worker_status)

          def normalize_workers launcher, now, config, stats
            worker_status = fetch(stats, :worker_status)

            if worker_status
              enhanced_by_index = enhanced_stats_by_worker_index(launcher)
              Array(worker_status).map do |worker_status_entry|
                normalize_cluster_worker worker_status_entry, now, config, enhanced_by_index
              end
            else
              [normalize_single_worker(now, config, stats)]
            end
          end

          def enhanced_stats_by_worker_index launcher
            return {} unless launcher.is_a?(Puma::Launcher)

            Array(launcher.workers).each_with_object({}) do |worker, hash|
              hash[worker.index] = worker.enhanced_stats
            end
          end

          def normalize_cluster_worker worker_status, now, config, enhanced_by_index
            index = fetch(worker_status, :index)
            handle = fetch(worker_status, :enhanced_stats) ||
                     enhanced_by_index[index] ||
                     {}
            items = Array(fetch(handle, :items)).map { |item| item_with_elapsed item, now }

            {
              "index" => index,
              "pid" => fetch(worker_status, :pid),
              "synced_at" => fetch(handle, :synced_at),
              "puma" => pick_puma_stats(fetch(worker_status, :last_status)),
              "process" => normalize_process(fetch(handle, :process)),
              "requests" => requests_section(
                items: items,
                config: config,
                truncated: fetch(handle, :truncated) || false,
                dropped_count: fetch(handle, :dropped_count) || 0
              )
            }
          end

          def normalize_single_worker now, config, stats
            registry_snapshot = CurrentRequests.instance.snapshot
            items = registry_snapshot["items"].map { |item| item_with_elapsed item, now }

            puma_stats = fetch(stats, :last_status) || stats

            {
              "index" => 0,
              "pid" => Process.pid,
              "synced_at" => now.iso8601,
              "puma" => pick_puma_stats(puma_stats),
              "process" => ProcessMetrics.read,
              "requests" => requests_section(
                items: items,
                config: config,
                truncated: registry_snapshot["truncated"],
                dropped_count: registry_snapshot["dropped_count"]
              )
            }
          end

          def item_with_elapsed item, now
            started = Time.iso8601 item["started_at"]
            item.merge "elapsed_ms" => ((now - started) * 1000).to_i
          rescue ArgumentError
            item.merge "elapsed_ms" => nil
          end

          def normalize_process raw
            return ProcessMetrics::EMPTY if raw.nil?

            {
              "rss_bytes" => fetch(raw, :rss_bytes),
              "cpu_percent" => fetch(raw, :cpu_percent)
            }
          end

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

          def pick_puma_stats last_status
            {
              "backlog" => fetch(last_status, :backlog) || 0,
              "running" => fetch(last_status, :running) || 0,
              "pool_capacity" => fetch(last_status, :pool_capacity) || 0,
              "max_threads" => fetch(last_status, :max_threads) || 0,
              "requests_count" => fetch(last_status, :requests_count) || 0
            }
          end

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
end
