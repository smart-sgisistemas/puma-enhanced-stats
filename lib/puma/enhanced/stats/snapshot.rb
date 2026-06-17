# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      # Assembles the public enhanced-stats JSON document (schema v1).
      #
      # Called by {Status} (+GET /enhanced-stats+) and +pumactl enhanced-stats+.
      #
      # In **single** mode, reads the live {CurrentRequests} registry and
      # {ProcessMetrics} for the current process. In **cluster** mode, merges
      # per-worker data synced from {WorkerHandle#enhanced_stats} via ping
      # messages enhanced by {WorkerWrite}.
      #
      # Limits and field definitions come from
      # +launcher.config.options[:enhanced_stats]+ or {Configuration.default}.
      #
      # @example Top-level shape
      #   {
      #     "schema_version" => 1,
      #     "meta" => { "mode" => "cluster", "worker_check_interval_seconds" => 5, ... },
      #     "summary" => { "workers_total" => 2, "requests_in_flight" => 3, ... },
      #     "workers" => [ { "index" => 0, "requests" => { ... }, ... } ]
      #   }
      #
      # @see schema/enhanced-stats-v1.json
      class Snapshot
        class << self
          # Builds the full enhanced-stats payload for a running launcher.
          #
          # @param launcher [Puma::Launcher]
          # @return [Hash{String => Object}]
          def build launcher
            now = Time.now.utc
            config = config_for launcher
            stats = launcher_stats launcher
            workers = normalize_workers launcher, now, config, stats

            {
              "schema_version" => 1,
              "meta" => meta(stats, now, launcher),
              "summary" => summary(workers),
              "workers" => workers
            }
          end

          # Reads a key from +hash+ whether stored as Symbol or String.
          #
          # Used throughout snapshot assembly for payloads that may come from
          # JSON (string keys) or Ruby objects (symbol keys).
          #
          # @param hash [Hash, nil]
          # @param key [Symbol, String]
          # @return [Object, nil]
          def fetch hash, key
            return nil unless hash

            hash[key] || hash[key.to_s] || hash[key.to_sym]
          end

          private

          # Resolves the active {Configuration} from launcher options or defaults.
          def config_for(launcher) = launcher.config.options[:enhanced_stats] || Configuration.default

          # Returns Puma launcher stats, supporting both +stats+ and +stats_hash+ APIs.
          def launcher_stats launcher
            if launcher.respond_to? :stats
              launcher.stats
            elsif launcher.respond_to? :stats_hash
              launcher.stats_hash
            else
              {}
            end
          end

          # Builds the +meta+ section with version and timing information.
          def meta stats, now, launcher
            {
              "collected_at" => now.iso8601,
              "gem_version" => VERSION,
              "puma_version" => Puma::Const::PUMA_VERSION,
              "ruby_version" => RUBY_VERSION,
              "mode" => cluster?(stats) ? "cluster" : "single",
              "worker_check_interval_seconds" => worker_check_interval_seconds(launcher)
            }
          end

          def worker_check_interval_seconds launcher
            interval = launcher.config.options[:worker_check_interval].to_i
            interval.positive? ? interval : 5
          end

          # Returns +true+ when +stats+ contains a +:worker_status+ key (cluster mode).
          def cluster?(stats) = fetch(stats, :worker_status)

          # Builds the +workers+ array for single or cluster mode.
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

          # Maps worker index to {WorkerHandle#enhanced_stats} from the launcher.
          def enhanced_stats_by_worker_index launcher
            return {} unless launcher.is_a?(Puma::Launcher)

            Array(launcher.workers).each_with_object({}) do |worker, hash|
              hash[worker.index] = worker.enhanced_stats
            end
          end

          # Normalizes one cluster worker entry into the schema v1 shape.
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

          # Normalizes the single-worker entry from the live registry.
          def normalize_single_worker now, config, stats
            registry_snapshot = CurrentRequests.snapshot
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

          # Adds +elapsed_ms+ to an in-flight item from its +started_at+ timestamp.
          def item_with_elapsed item, now
            started = Time.iso8601 item["started_at"]
            item.merge "elapsed_ms" => ((now - started) * 1000).to_i
          rescue ArgumentError
            item.merge "elapsed_ms" => nil
          end

          # Normalizes process metrics to string keys with nil fallbacks.
          def normalize_process raw
            return ProcessMetrics::EMPTY unless raw

            {
              "rss_bytes" => fetch(raw, :rss_bytes),
              "cpu_percent" => fetch(raw, :cpu_percent)
            }
          end

          # Builds the +requests+ section with meta counters and item list.
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

          # Extracts standard Puma thread pool stats with zero defaults.
          def pick_puma_stats last_status
            {
              "backlog" => fetch(last_status, :backlog) || 0,
              "running" => fetch(last_status, :running) || 0,
              "pool_capacity" => fetch(last_status, :pool_capacity) || 0,
              "max_threads" => fetch(last_status, :max_threads) || 0,
              "requests_count" => fetch(last_status, :requests_count) || 0
            }
          end

          # Aggregates cross-worker totals for the +summary+ section.
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
