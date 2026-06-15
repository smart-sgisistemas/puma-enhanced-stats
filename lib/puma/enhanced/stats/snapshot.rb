# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      # Builds the public enhanced-stats JSON document (schema v1).
      #
      # Used by {Status} and +pumactl enhanced-stats+.
      #
      # In single mode, reads the live {CurrentRequestsRegistry} and
      # {ProcessMetrics.read}. In cluster mode, merges data synced from workers
      # via {WorkerHandle}. Limits and field extractors come from
      # +launcher.config.options[:enhanced_stats]+ or {Configuration.default}.
      #
      # @see Normalizer
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
              "summary" => Normalizer.summary(workers),
              "workers" => workers
            }
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

          def cluster?(stats) = Normalizer.fetch(stats, :worker_status)

          def normalize_workers launcher, now, config, stats
            worker_status = Normalizer.fetch(stats, :worker_status)

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
            index = Normalizer.fetch(worker_status, :index)
            handle = Normalizer.fetch(worker_status, :enhanced_stats) ||
                     enhanced_by_index[index] ||
                     {}
            items = Array(Normalizer.fetch(handle, :items)).map do |item|
              Normalizer.item_with_elapsed item, now
            end

            {
              "index" => index,
              "pid" => Normalizer.fetch(worker_status, :pid),
              "synced_at" => Normalizer.fetch(handle, :synced_at),
              "puma" => Normalizer.pick_puma_stats(Normalizer.fetch(worker_status, :last_status)),
              "process" => Normalizer.normalize_process(Normalizer.fetch(handle, :process)),
              "requests" => Normalizer.requests_section(
                items: items,
                config: config,
                truncated: Normalizer.fetch(handle, :truncated) || false,
                dropped_count: Normalizer.fetch(handle, :dropped_count) || 0
              )
            }
          end

          def normalize_single_worker now, config, stats
            registry_snapshot = CurrentRequestsRegistry.instance.snapshot
            items = registry_snapshot["items"].map { |item| Normalizer.item_with_elapsed item, now }

            puma_stats = Normalizer.fetch(stats, :last_status) || stats

            {
              "index" => 0,
              "pid" => Process.pid,
              "synced_at" => now.iso8601,
              "puma" => Normalizer.pick_puma_stats(puma_stats),
              "process" => ProcessMetrics.read,
              "requests" => Normalizer.requests_section(
                items: items,
                config: config,
                truncated: registry_snapshot["truncated"],
                dropped_count: registry_snapshot["dropped_count"]
              )
            }
          end
        end
      end
    end
  end
end
