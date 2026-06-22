# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      class Snapshot
        SCHEMA_VERSION = 1

        def initialize worker_check_interval:, server: nil, workers: nil
          @worker_check_interval = worker_check_interval
          @server = server
          @workers = workers
        end

        def to_h
          rows = worker_rows

          {
            schema_version: SCHEMA_VERSION,
            meta: meta,
            summary: summarize(rows),
            workers: rows
          }
        end

        private

        def worker_rows
          if @workers
            @workers.sort_by(&:index).map { |worker| cluster_row worker }
          else
            [build_row(
              index: 0,
              pid: Process.pid,
              registry: CurrentRequests.snapshot.merge(@server&.stats || {}).merge(synced_at: collected_at)
            )]
          end
        end

        def cluster_row worker
          build_row(
            index: worker.index,
            pid: worker.pid,
            registry: worker.last_enhanced_stats
          )
        end

        def build_row index:, pid:, registry:
          items = registry[:items] || []
          config = CurrentRequests.config

          {
            index: index,
            pid: pid,
            synced_at: registry[:synced_at],
            puma: Puma::Server::STAT_METHODS.to_h { |key| [key, registry[key] || 0] },
            requests: {
              meta: {
                count: items.size,
                request_limit: config.request_limit,
                limit_policy: config.limit_policy.to_s,
                truncated: registry[:truncated] || false,
                dropped_count: registry[:dropped_count] || 0
              },
              items: items
            }
          }
        end

        def meta
          {
            collected_at: collected_at,
            gem_version: VERSION,
            puma_version: Puma::Const::PUMA_VERSION,
            ruby_version: RUBY_VERSION,
            mode: @workers ? "cluster" : "single",
            worker_check_interval_seconds: @worker_check_interval
          }
        end

        def collected_at
          @collected_at ||= Time.now.utc.iso8601
        end

        def summarize workers
          reporting = workers.count { |row| row[:synced_at] }

          {
            workers_total: workers.size,
            workers_reporting: reporting,
            workers_stale: workers.size - reporting,
            requests_in_flight: workers.sum { |row| row.dig(:requests, :meta, :count) || 0 },
            requests_dropped_total: workers.sum { |row| row.dig(:requests, :meta, :dropped_count) || 0 },
            requests_truncated: workers.any? { |row| row.dig(:requests, :meta, :truncated) },
            backlog_total: workers.sum { |row| row.dig(:puma, :backlog) || 0 },
            busy_threads_total: workers.sum { |row| row.dig(:puma, :busy_threads) || 0 },
            max_threads_total: workers.sum { |row| row.dig(:puma, :max_threads) || 0 },
            pool_capacity_total: workers.sum { |row| row.dig(:puma, :pool_capacity) || 0 }
          }
        end
      end
    end
  end
end
