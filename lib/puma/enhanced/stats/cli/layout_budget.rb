# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module CLI
        # Computes vertical and horizontal space for dashboard sections.
        #
        # Reserves lines for HEADER, optional SYSTEM/PROCESSES/FOOTER, and divides
        # remaining height among worker boxes and in-flight request rows.
        #
        # @see DashboardRenderer
        # @see Runner#render_frame
        class LayoutBudget
          HEADER_LINES = 3
          SYSTEM_LINES = 6
          PROCESSES_LINES = 6
          SUMMARY_LINES = 7
          FOOTER_LINES = 3
          WORKER_METRICS_LINES = 8
          WORKER_OVERHEAD = 4

          # @return [Integer] terminal column count
          # @return [Integer] terminal row count
          # @return [Boolean] two-column worker grid enabled
          # @return [Array<String>] layout fallback warnings shown above SUMMARY
          attr_reader :cols, :rows, :compact_grid, :warnings

          # @param rows [Integer] terminal height
          # @param cols [Integer] terminal width
          # @param options [Options]
          # @param worker_count [Integer] number of workers in the payload
          def initialize rows, cols, options, worker_count:
            @rows = rows
            @cols = cols
            @options = options
            @worker_count = [worker_count, 1].max
            @warnings = []
            @compact_grid = compact_grid? worker_count
          end

          # @return [Integer] row budget shared by all worker sections
          def available_for_workers
            reserved = HEADER_LINES + SUMMARY_LINES
            reserved += SYSTEM_LINES + PROCESSES_LINES if @options.top?
            reserved += FOOTER_LINES if @options.watch?
            [@rows - reserved, WORKER_METRICS_LINES].max
          end

          # @param label_cols [Integer] columns reserved for metric labels
          # @return [Integer] bar width in characters
          def bar_width label_cols: 22
            [@cols - label_cols - 6, 8].max
          end

          # @param items [Array<Hash>] in-flight request items for one worker
          # @param overflow_fields [Integer] nested overflow lines per request
          # @return [Integer] max requests to render in the worker box
          def max_requests_for_worker items, overflow_fields: 0
            budget = (available_for_workers / @worker_count) - WORKER_OVERHEAD
            budget = [budget, 3].max
            per_request = 1 + overflow_fields
            [budget / per_request, items.size].min
          end

          # @return [Integer] inner width for worker content (half width in compact grid)
          def worker_inner_width
            return (@cols - 3) / 2 if @compact_grid

            @cols
          end

          private

          def compact_grid? worker_count
            return false unless @options.compact?

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
