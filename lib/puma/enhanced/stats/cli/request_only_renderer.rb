# frozen_string_literal: true

require_relative "box"
require_relative "format"
require_relative "worker_list"

module Puma
  module Enhanced
    module Stats
      module CLI
        # Minimal view: worker backlog/capacity summary and in-flight requests.
        #
        # Selected by +--request-only+.
        class RequestOnlyRenderer
          SUMMARY_HEADERS = %w[WORKER BACKLOG CAPACITY THREADS].freeze
          SUMMARY_WIDTHS = [6, 8, 12, 10].freeze

          def initialize(options) = @options = options

          # @param payload [Hash{Symbol => Object}]
          # @param budget [LayoutBudget]
          # @param refresh_interval [Integer, nil]
          # @return [String]
          def render payload, budget, refresh_interval: nil
            workers = WorkerList.prepare payload[:workers] || [], @options
            parts = [render_workers_summary(workers, budget)]
            parts.concat workers.map { |worker| render_worker_requests worker, budget }
            parts << render_footer(refresh_interval, budget) if @options.watch? && refresh_interval
            parts.join "\n\n"
          end

          private

          def render_workers_summary workers, budget
            box = Box.new budget.cols
            lines = [Format.table_row(SUMMARY_HEADERS, SUMMARY_WIDTHS)]
            workers.each do |worker|
              puma = worker[:puma] || {}
              max = puma[:max_threads].to_i
              lines << Format.table_row(
                [
                  worker[:index].to_s,
                  puma[:backlog].to_s,
                  "#{puma[:pool_capacity]}/#{max}",
                  "#{puma[:running]}/#{max}"
                ],
                SUMMARY_WIDTHS
              )
            end
            lines = ["No workers reporting"] if workers.empty?
            box.draw title: "WORKERS", lines: lines
          end

          def render_worker_requests worker, budget
            items = worker.dig(:requests, :items) || []
            lines = if items.empty?
                      ["No in-flight requests"]
                    else
                      items.map { |item| format_request item, budget }
                    end
            title = "WORKER #{worker[:index]} ─ #{items.size} in-flight"
            Box.new(budget.cols).draw title: title, lines: lines
          end

          def format_request item, budget
            elapsed = Format.elapsed_ms(item[:elapsed_ms]).ljust(8)
            method = (item[:method] || "-").to_s.ljust(6)
            path = Format.truncate(item[:path_info] || "-", [budget.cols - 18, 12].max)
            "#{elapsed} #{method} #{path}"
          end

          def render_footer refresh_interval, budget
            Box.new(budget.cols).draw(
              title: "FOOTER",
              lines: ["Refresh #{refresh_interval}s (worker_check_interval) │ Ctrl+C quit"]
            )
          end
        end
      end
    end
  end
end
