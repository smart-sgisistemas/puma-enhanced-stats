# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module CLI
        # Computes row and column budget for dashboard layout.
        #
        # Reserves space for fixed sections (HEADER, SUMMARY, optional
        # SYSTEM/PROCESSES/FOOTER) and divides the remainder among worker
        # boxes and in-flight request rows. Unusable +--compact+ combinations
        # append human-readable messages to {#warnings}.
        class LayoutBudget
          HEADER_LINES = 3
          SYSTEM_LINES = 6
          PROCESSES_LINES = 6
          SUMMARY_LINES = 7
          FOOTER_LINES = 3
          WORKER_METRICS_LINES = 8
          WORKER_OVERHEAD = 4

          attr_reader :cols, :rows, :compact_grid, :warnings

          def initialize rows, cols, options, worker_count:
            @rows = rows
            @cols = cols
            @options = options
            @worker_count = [worker_count, 1].max
            @warnings = []
            @compact_grid = compact_grid? worker_count
          end

          def available_for_workers
            reserved = HEADER_LINES + SUMMARY_LINES
            reserved += SYSTEM_LINES + PROCESSES_LINES if @options.top?
            reserved += FOOTER_LINES if @options.watch
            [@rows - reserved, WORKER_METRICS_LINES].max
          end

          def bar_width(label_cols: 22) = [@cols - label_cols - 6, 8].max

          # @param overflow_fields [Integer] nested overflow lines per request row
          def max_requests_for_worker items, overflow_fields: 0
            budget = (available_for_workers / @worker_count) - WORKER_OVERHEAD
            budget = [budget, 3].max
            per_request = 1 + overflow_fields
            [budget / per_request, items.size].min
          end

          def worker_inner_width = @compact_grid ? (@cols - 3) / 2 : @cols

          private

          def compact_grid? worker_count
            return false unless @options.compact

            if worker_count > 2
              @warnings << "--compact supports at most 2 workers; using stacked layout"
              return false
            end

            if @cols < 120
              @warnings << "--compact requires terminal width >= 120; using stacked layout"
              return false
            end

            true
          end
        end
      end
    end
  end
end
