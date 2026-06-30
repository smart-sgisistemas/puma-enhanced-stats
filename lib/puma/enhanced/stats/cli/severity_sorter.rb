# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module CLI
        # Default worker / process sort by severity.
        module SeveritySorter
          module_function

          def sort_workers(workers, process_by_pid:, interval:, mode:, collected_at:)
            workers.sort_by do |worker|
              puma = worker["puma"] || {}
              sync = SyncFreshness.evaluate(
                synced_at: worker["synced_at"],
                collected_at: collected_at,
                interval_seconds: interval,
                mode: mode
              )
              sample = process_by_pid[worker["pid"]]
              in_flight = worker.dig("requests", "items")&.size.to_i
              max_threads = puma["max_threads"].to_i
              inflight_ratio = max_threads.positive? ? in_flight.to_f / max_threads : 0.0
              backlog = puma["backlog"].to_i

              [
                backlog.positive? ? 0 : 1,
                worker["synced_at"].nil? ? 0 : 1,
                sync.badge == :crit ? 0 : 1,
                sync.badge == :warn ? 0 : 1,
                -inflight_ratio,
                -(sample&.cpu_percent.to_f),
                worker["index"].to_i
              ]
            end
          end

          def sort_process_rows(rows)
            rows.sort_by do |row|
              [
                row[:backlog_sort].to_i.positive? ? 0 : 1,
                -row[:sort_cpu].to_f,
                row[:sort_index].to_i
              ]
            end
          end
        end
      end
    end
  end
end
