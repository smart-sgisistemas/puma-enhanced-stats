# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      # Builds the enhanced-stats JSON document (schema v1).
      #
      # Instantiate with a Puma launcher, then call {#build}. Assembly runs in
      # two steps: {#workers} reads Puma +worker_status+ (or a synthetic row in
      # single mode), then {#enhanced_workers} maps each row into the public
      # schema (+puma+, +process+, +requests+).
      #
      # In **cluster** mode, enhanced data comes from {WorkerHandle#enhanced_stats}
      # via +@enhanced_by_index+ (not from {Puma::Cluster#stats}, so +pumactl stats+
      # stays unchanged). In **single** mode, the lone row uses {CurrentRequests.snapshot}.
      #
      # @example
      #   Snapshot.new(launcher).build
      #
      # @see schema/enhanced-stats-v1.json
      class Snapshot
        # Public contract version; exposed as +schema_version+ in the JSON document.
        SCHEMA_VERSION = 1

        # @!attribute [r] config
        #   @return [Configuration]
        # @!attribute [r] stats
        #   @return [Hash{Symbol => Object}] raw Puma launcher stats
        # @!attribute [r] now
        #   @return [Time] UTC timestamp used for +collected_at+
        attr_reader :config, :stats, :now

        # @param launcher [Puma::Launcher]
        # @param now [Time] collection timestamp (UTC); drives +collected_at+
        # @return [void]
        def initialize launcher, now: Time.now.utc
          @now = now
          @config = launcher.config.options[:enhanced_stats] || Configuration.default
          @worker_check_interval = launcher.config.options[:worker_check_interval]
          @stats = launcher.stats
          @enhanced_by_index =
            if launcher.is_a? Puma::Launcher
              launcher.workers.to_a.to_h { |worker| [worker.index, worker.enhanced_stats] }
            else
              {}
            end
        end

        # Assembles the schema v1 document.
        #
        # @return [Hash{Symbol => Object}]
        def build
          enhanced = enhanced_workers

          {
            schema_version: SCHEMA_VERSION,
            meta: meta,
            summary: summary(enhanced),
            workers: enhanced
          }
        end

        # Convenience constructor that builds the document immediately.
        #
        # @param launcher [Puma::Launcher]
        # @return [Hash{Symbol => Object}] same shape as {#build}
        def self.build(launcher) = new(launcher).build

        private

        # Cluster mode is indicated by the presence of +worker_status+ in Puma stats
        # (see {Puma::Cluster#stats}), including when the worker list is empty.
        #
        # @return [Boolean]
        def clustered? = stats.key?(:worker_status)

        # @return [Hash{Symbol => Object}] +meta+ section
        def meta
          {
            collected_at: now.iso8601,
            gem_version: VERSION,
            puma_version: Puma::Const::PUMA_VERSION,
            ruby_version: RUBY_VERSION,
            mode: clustered? ? "cluster" : "single",
            worker_check_interval_seconds: @worker_check_interval
          }
        end

        # @param enhanced_workers [Array<Hash{Symbol => Object}>]
        # @return [Hash{Symbol => Object}] +summary+ section
        def summary enhanced_workers
          workers_total = enhanced_workers.size
          workers_reporting = enhanced_workers.count { |worker| worker[:synced_at] }

          {
            workers_total: workers_total,
            workers_reporting: workers_reporting,
            workers_stale: workers_total - workers_reporting,
            requests_in_flight: enhanced_workers.sum { |worker| worker.dig(:requests, :meta, :count) || 0 },
            requests_dropped_total: enhanced_workers.sum { |worker| worker.dig(:requests, :meta, :dropped_count) || 0 },
            requests_truncated: enhanced_workers.any? { |worker| worker.dig(:requests, :meta, :truncated) },
            backlog_total: enhanced_workers.sum { |worker| worker.dig(:puma, :backlog) || 0 },
            busy_threads_total: enhanced_workers.sum { |worker| worker.dig(:puma, :busy_threads) || 0 },
            max_threads_total: enhanced_workers.sum { |worker| worker.dig(:puma, :max_threads) || 0 },
            pool_capacity_total: enhanced_workers.sum { |worker| worker.dig(:puma, :pool_capacity) || 0 }
          }
        end

        # Puma +worker_status+ rows with +enhanced_stats+ attached (cluster),
        # or one synthetic row in single mode.
        #
        # @return [Array<Hash{Symbol => Object}>]
        def workers
          if clustered?
            stats[:worker_status].map do |status|
              status.merge enhanced_stats: @enhanced_by_index[status[:index]] || { items: [] }
            end
          else
            [{
              index: 0,
              pid: Process.pid,
              last_status: stats[:last_status] || stats,
              enhanced_stats: CurrentRequests.snapshot.merge(synced_at: now.iso8601)
            }]
          end
        end

        # Maps {#workers} into the schema v1 +workers+ array.
        #
        # @return [Array<Hash{Symbol => Object}>]
        def enhanced_workers
          workers.map do |worker|
            enhanced = worker[:enhanced_stats]

            {
              index: worker[:index],
              pid: worker[:pid],
              synced_at: enhanced[:synced_at],
              puma: Puma::Server::STAT_METHODS.to_h { |key| [key, (worker[:last_status] || {})[key] || 0] },
              process: enhanced[:process] || ProcessMetrics::EMPTY,
              requests: {
                meta: {
                  count: enhanced[:items].size,
                  request_limit: config.request_limit,
                  limit_policy: config.limit_policy.to_s,
                  truncated: enhanced[:truncated] || false,
                  dropped_count: enhanced[:dropped_count] || 0
                },
                items: enhanced[:items]
              }
            }
          end
        end
      end
    end
  end
end
