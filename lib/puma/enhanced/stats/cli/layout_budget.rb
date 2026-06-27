# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module CLI
        # Computes row and column budget for dashboard layout.
        class LayoutBudget
          HEADER_LINES = 3
          TOP_LINES = 6
          PROCESSES_LINES = 6
          SUMMARY_LINES = 7
          OUTSIDERS_LINES = 5
          FOOTER_LINES = 2
          WORKER_METRICS_LINES = 8
          WORKER_OVERHEAD = 5

          attr_reader :cols, :rows, :layout, :warnings, :saved_layout, :unified_box_width

          attr_writer :unified_box_width

          def capped_cols = LayoutGrid.cap_cols(@cols)

          def box_cols = @unified_box_width || capped_cols

          def make_box(fixed_width: box_cols) = Box.new(capped_cols, fixed_width: fixed_width)

          def worker_box_cols
            if %w[two_column grid].include?(@layout)
              worker_inner_width
            else
              box_cols
            end
          end

          def initialize(rows, cols, options, worker_count:, layout: nil, saved_layout: nil)
            @rows = rows
            @cols = cols
            @options = options
            @worker_count = [worker_count, 1].max
            @warnings = []
            @saved_layout = saved_layout || options.frame_layout
            @layout = layout || options.frame_layout
            @show_top = @options.top? && @layout != "compact"
            apply_compact_rules!
          end

          def available_for_workers
            reserved = HEADER_LINES + SUMMARY_LINES + FOOTER_LINES
            reserved += TOP_LINES + PROCESSES_LINES if @show_top
            reserved += OUTSIDERS_LINES if @options.show_outsiders?
            [@rows - reserved, WORKER_METRICS_LINES].max
          end

          def metric_content_width(box_width = box_cols)
            LayoutGrid.content_width(box_width)
          end

          def bar_width = Bar::BAR_WIDTH

          def max_requests_for_worker(items, overflow_fields: 0)
            workers = visible_worker_slots
            budget = (available_for_workers / workers) - WORKER_OVERHEAD
            budget = [budget, 3].max
            per_request = 1 + overflow_fields
            count = budget / per_request
            count = [count, 1].max if items.any? && count.zero?
            [count, items.size].min
          end

          def worker_inner_width
            width = box_cols
            case @layout
            when "two_column", "grid" then (width - 3) / 2
            else width
            end
          end

          def show_top? = @show_top

          def request_display_mode
            mode = @options.request_display
            return mode unless mode == "auto"

            @cols >= 120 ? "inline" : "stack"
          end

          private

          def visible_worker_slots
            case @layout
            when "focus" then 1
            when "two_column", "grid" then 2
            when "compact" then 1
            else @worker_count
            end
          end

          def apply_compact_rules!
            return if @layout != "compact"

            @options.no_top = true if @options.frame_layout == "compact"
          end
        end
      end
    end
  end
end
