# frozen_string_literal: true

require_relative "../version"

module Puma
  module Enhanced
    module Stats
      module CLI
        # Normalized read model for enhanced-stats JSON v1 (Puma-aligned).
        #
        # Cluster payloads expose +worker_status+ and aggregate +*_total+ keys.
        # Single payloads expose flat pool counters and +requests+ at the root.
        class PayloadView
          DEFAULT_SYNC_INTERVAL = 5
          CLUSTER_PUMA_KEYS = %w[backlog running pool_capacity busy_threads max_threads].freeze
          SINGLE_PUMA_KEYS = %w[
            backlog running pool_capacity busy_threads max_threads
            io_threads backlog_max requests_count reactor_max
          ].freeze

          class << self
            def wrap(payload, sync_interval: nil, server_pid: nil)
              if payload.is_a?(self)
                payload
              else
                new(payload, sync_interval: sync_interval, server_pid: server_pid)
              end
            end
          end

          def initialize(raw, sync_interval: nil, server_pid: nil)
            @raw = raw
            @sync_interval = sync_interval
            @server_pid = server_pid
          end

          def [](key) = @raw[key]
          def to_h = @raw
          def raw = @raw

          def cluster? = @raw.key?("worker_status")
          def single? = !cluster?
          def mode = cluster? ? "cluster" : "single"
          def collected_at = @raw["collected_at"]
          def gem_version = @raw.dig("versions", "puma-enhanced-stats") || Stats::VERSION

          def worker_check_interval_seconds
            return 0 if single?

            interval = @sync_interval || @raw.dig("_cli", "worker_check_interval_seconds")
            interval = interval.to_i
            interval.positive? ? interval : DEFAULT_SYNC_INTERVAL
          end

          def workers_total = cluster? ? @raw["workers_total"].to_i : 1
          def workers_reporting = cluster? ? @raw["workers_reporting"].to_i : 1
          def workers_stale = cluster? ? @raw["workers_stale"].to_i : 0
          def requests_in_flight = @raw["requests_in_flight"].to_i

          def backlog_total = cluster? ? @raw["backlog_total"].to_i : @raw["backlog"].to_i
          def busy_threads_total = cluster? ? @raw["busy_threads_total"].to_i : @raw["busy_threads"].to_i
          def max_threads_total = cluster? ? @raw["max_threads_total"].to_i : @raw["max_threads"].to_i
          def pool_capacity_total = cluster? ? @raw["pool_capacity_total"].to_i : @raw["pool_capacity"].to_i
          def running_total = cluster? ? sum_worker_puma("running") : @raw["running"].to_i

          def workers
            @workers ||= if cluster?
                           Array(@raw["worker_status"]).map { |worker| normalize_cluster_worker(worker) }
                         else
                           [normalize_single_worker]
                         end
          end

          private

          def sum_worker_puma(key)
            Array(@raw["worker_status"]).sum { |row| row.dig("last_enhanced_status", key).to_i }
          end

          def normalize_cluster_worker(worker)
            puma = extract_puma_stats(worker["last_enhanced_status"] || {}, CLUSTER_PUMA_KEYS)
            requests = Array(worker["requests"])
            {
              "index" => worker["index"],
              "pid" => worker["pid"],
              "synced_at" => worker["last_enhanced_checkin"],
              "puma" => puma,
              "requests" => { "items" => requests },
              "single" => false
            }
          end

          def normalize_single_worker
            puma = extract_puma_stats(@raw, SINGLE_PUMA_KEYS)
            requests = Array(@raw["requests"])
            {
              "index" => 0,
              "pid" => @server_pid,
              "synced_at" => collected_at,
              "puma" => puma,
              "requests" => { "items" => requests },
              "single" => true
            }
          end

          def extract_puma_stats(stats, keys)
            keys.each_with_object({}) do |key, hash|
              hash[key] = stats[key] if stats.key?(key)
            end
          end
        end
      end
    end
  end
end
