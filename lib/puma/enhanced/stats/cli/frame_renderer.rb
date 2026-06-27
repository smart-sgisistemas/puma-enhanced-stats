# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module CLI
        # Composes HEADER → TOP → PROCESSES → SUMMARY → WORKERS → FOOTER.
        class FrameRenderer
          LAYOUTS = %w[stacked two_column split grid focus compact].freeze
          SECTION_GAP = "\n\n\n"

          def initialize(options, budget, bar, colors)
            @options = options
            @budget = budget
            @bar = bar
            @colors = colors
          end

          def render(payload, host:, process_by_pid:, attribution:, scroll:, interval:, master_pid:)
            if LayoutGrid.too_narrow?(@budget.cols)
              return narrow_frame(@budget.cols)
            end

            layout = @budget.layout
            @budget.unified_box_width = Box.unified_width(collect_box_specs(
              payload, host, process_by_pid, attribution, scroll, interval, master_pid, layout
            ), @budget.capped_cols)

            parts = []
            parts << HeaderRenderer.new.render(payload, @budget)
            parts.concat(top_section(payload, host, process_by_pid, attribution, interval, master_pid)) if @budget.show_top?
            parts << SummaryRenderer.new(@bar, @colors).render(payload, @budget, attribution: attribution)
            parts.concat worker_sections payload, process_by_pid, scroll, interval, layout
            parts << OutsidersRenderer.new.render(attribution, @budget) if show_outsiders?(attribution)
            parts << FooterRenderer.new.render(@options, @budget, refresh_interval: interval, layout_hint: layout_hint)
            parts.compact.join SECTION_GAP
          end

          private

          def collect_box_specs(payload, host, process_by_pid, attribution, scroll, interval, master_pid, layout)
            specs = [HeaderRenderer.new.box_spec(payload, budget: @budget)]

            if @budget.show_top?
              top = TopRenderer.new(
                @options, @bar, colors: @colors, host: host, attribution: attribution,
                master_pid: master_pid, process_by_pid: process_by_pid
              )
              specs << top.box_spec_top(@budget)
              specs << top.box_spec_processes(payload, refresh_interval: interval, budget: @budget)
            end

            specs << SummaryRenderer.new(@bar, @colors).box_spec(payload, attribution: attribution, budget: @budget)
            specs.concat worker_box_specs(payload, process_by_pid, scroll, interval, layout)
            specs << OutsidersRenderer.new.box_spec(attribution) if show_outsiders?(attribution)
            specs << FooterRenderer.new.box_spec(
              @options, @budget, refresh_interval: interval, layout_hint: layout_hint
            )
            specs.compact
          end

          def worker_box_specs(payload, process_by_pid, scroll, interval, layout)
            meta = payload["meta"] || {}
            workers = prepare_workers payload, process_by_pid, meta
            renderer = WorkerRenderer.new @options, @bar, @colors
            interval_val = meta["worker_check_interval_seconds"].to_i
            interval_val = 5 if interval_val <= 0

            case layout
            when "focus"
              index = scroll.focus_worker || @options.focus_worker || 0
              worker = workers.find { |w| w["index"].to_i == index.to_i } || workers.first
              worker ? [worker_spec(renderer, worker, process_by_pid, meta, scroll, interval_val)] : []
            when "compact"
              worker = workers.max_by { |w| w.dig("requests", "items")&.size.to_i } || workers.first
              worker ? [worker_spec(renderer, worker, process_by_pid, meta, scroll, interval_val)] : []
            else
              workers.map { |worker| worker_spec(renderer, worker, process_by_pid, meta, scroll, interval_val) }
            end
          end

          def worker_spec(renderer, worker, process_by_pid, meta, scroll, interval)
            renderer.box_spec worker, @budget, process_by_pid: process_by_pid,
                              collected_at: meta["collected_at"], interval: interval,
                              mode: meta["mode"], scroll: scroll
          end

          def top_section(payload, host, process_by_pid, attribution, interval, master_pid)
            top = TopRenderer.new(
              @options, @bar, colors: @colors, host: host, attribution: attribution,
              master_pid: master_pid, process_by_pid: process_by_pid
            )
            [top.render_top(@budget), top.render_processes(payload, @budget, refresh_interval: interval)]
          end

          def worker_sections(payload, process_by_pid, scroll, interval, layout)
            meta = payload["meta"] || {}
            workers = prepare_workers payload, process_by_pid, meta
            renderer = WorkerRenderer.new @options, @bar, @colors

            case layout
            when "two_column", "grid"
              render_worker_grid workers, renderer, process_by_pid, meta, scroll, interval
            when "focus"
              index = scroll.focus_worker || @options.focus_worker || 0
              worker = workers.find { |w| w["index"].to_i == index.to_i } || workers.first
              worker ? [renderer.render(worker, @budget, process_by_pid: process_by_pid,
                                                    collected_at: meta["collected_at"],
                                                    interval: interval, mode: meta["mode"],
                                                    scroll: scroll)] : []
            when "compact"
              worker = workers.max_by { |w| w.dig("requests", "items")&.size.to_i } || workers.first
              worker ? [renderer.render(worker, @budget, process_by_pid: process_by_pid,
                                                    collected_at: meta["collected_at"],
                                                    interval: interval, mode: meta["mode"],
                                                    scroll: scroll)] : []
            else
              workers.map do |worker|
                renderer.render worker, @budget, process_by_pid: process_by_pid,
                                collected_at: meta["collected_at"], interval: interval,
                                mode: meta["mode"], scroll: scroll
              end
            end
          end

          def render_worker_grid(workers, renderer, process_by_pid, meta, scroll, interval)
            pairs = workers.each_slice(2).map do |slice|
              slice.map do |worker|
                renderer.render worker, @budget, process_by_pid: process_by_pid,
                                collected_at: meta["collected_at"], interval: interval,
                                mode: meta["mode"], scroll: scroll
              end
            end
            pairs.map { |boxes| merge_boxes boxes }
          end

          def merge_boxes(boxes)
            lines = boxes.flat_map { |box| box.split "\n" }
            return lines.join "\n" if boxes.size == 1

            left, right = boxes.map { |b| b.split "\n" }
            inner = @budget.worker_inner_width
            max = [left.size, right.size].max
            (0...max).map do |i|
              left_line = left[i].to_s
              right_line = right[i].to_s
              gap = inner - Format.display_length(left_line)
              gap = 0 if gap.negative?
              "#{left_line}#{' ' * gap}  #{right_line}"
            end.join "\n"
          end

          def prepare_workers(payload, process_by_pid, meta)
            workers = payload["workers"] || []
            interval = meta["worker_check_interval_seconds"].to_i
            interval = 5 if interval <= 0
            sorted = SeveritySorter.sort_workers(
              workers, process_by_pid: process_by_pid,
              interval: interval, mode: meta["mode"], collected_at: meta["collected_at"]
            )
            if @options.focus_worker
              sorted.select { |w| w["index"].to_i == @options.focus_worker.to_i }
            else
              sorted
            end
          end

          def show_outsiders?(attribution)
            @options.show_outsiders? && attribution.outsiders.any?
          end

          def layout_hint
            return nil unless @budget.saved_layout != @budget.layout

            "layout: #{@budget.layout} (saved #{@budget.saved_layout}, need #{LayoutRegistry::MODES[@budget.saved_layout]} cols)"
          end

          def narrow_frame(cols)
            width = [cols, 10].max
            message = LayoutGrid.narrow_error_message(cols)
            lines = Format.wrap(message, width - 3)
            Box.new(width).draw(
              title: "DISPLAY ERROR",
              lines: lines
            )
          end
        end
      end
    end
  end
end
