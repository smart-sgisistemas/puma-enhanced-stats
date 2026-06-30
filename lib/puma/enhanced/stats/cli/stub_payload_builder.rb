# frozen_string_literal: true

require "json"
require "time"

require_relative "../version"

module Puma
  module Enhanced
    module Stats
      module CLI
        # Builds enhanced-stats v1 payloads for the stub HTTP server.
        class StubPayloadBuilder
          FIXTURE_DIR = File.expand_path "../../../../../spec/fixtures/stub", __dir__

          class << self
            def build(scenario:, workers: 3, stale: 0)
              path = File.join FIXTURE_DIR, "#{scenario_file scenario}.json"
              payload = JSON.parse File.read path
              if scenario == "single"
                payload["collected_at"] = Time.now.utc.iso8601
                payload["versions"] ||= {}
                payload["versions"]["puma-enhanced-stats"] = Stats::VERSION
                return payload
              end

              customize! payload, workers: workers, stale: stale
              payload
            end

            private

            def scenario_file(scenario)
              case scenario
              when "mixed" then "mixed-cluster"
              when "stale" then "stale-worker"
              when "truncated" then "truncated-paths"
              when "single" then "single-server"
              when "custom" then "mixed-cluster"
              else scenario
              end
            end

            def customize!(payload, workers:, stale:)
              payload["collected_at"] = Time.now.utc.iso8601
              payload["versions"] ||= {}
              payload["versions"]["puma-enhanced-stats"] = Stats::VERSION

              list = Array(payload["worker_status"]).first(workers)
              stale.times { |i| list[-(i + 1)]["last_enhanced_checkin"] = nil if list[-(i + 1)] }
              payload["worker_status"] = list

              reporting = list.count { |row| !row["last_enhanced_checkin"].nil? }
              requests = list.sum { |row| Array(row["requests"]).size }
              payload["workers_total"] = list.size
              payload["workers_reporting"] = reporting
              payload["workers_stale"] = list.size - reporting
              payload["requests_in_flight"] = requests
              payload["workers"] = list.size
              payload["booted_workers"] = list.size
              recompute_totals! payload, list
            end

            def recompute_totals!(payload, list)
              payload["backlog_total"] = sum_status(list, "backlog")
              payload["busy_threads_total"] = sum_status(list, "busy_threads")
              payload["max_threads_total"] = sum_status(list, "max_threads")
              payload["pool_capacity_total"] = sum_status(list, "pool_capacity")
            end

            def sum_status(list, key)
              list.sum { |row| row.dig("last_enhanced_status", key).to_i }
            end
          end
        end
      end
    end
  end
end
