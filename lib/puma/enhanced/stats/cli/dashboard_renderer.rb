# frozen_string_literal: true

require_relative "box"
require_relative "format"
require_relative "summary_aggregator"
require_relative "request_table"

module Puma
  module Enhanced
    module Stats
      module CLI
        # Renders HEADER, SUMMARY, worker boxes, and FOOTER sections.
        #
        # Composes {Box}, {SummaryAggregator}, {RequestTable}, and {Bar} output.
        # Worker layout is stacked by default; {LayoutBudget#compact_grid} enables
        # a two-column grid.
        #
        # @see Runner#render_frame
        class DashboardRenderer
          # @param options [Options]
          # @param colors [Colors]
          # @param bar [Bar]
          def initialize options, colors, bar
            @options = options
            @colors = colors
            @bar = bar
          end

          # @param payload [Hash] enhanced-stats JSON
          # @param budget [LayoutBudget]
          # @return [String] double-bordered HEADER box
          def render_header payload, budget
            meta = payload["meta"] || {}
            title = "PUMA ENHANCED STATS ─ v#{meta['gem_version'] || VERSION}"
            line = [
              "Mode #{meta['mode']}",
              "Puma #{meta['puma_version']}",
              "Ruby #{meta['ruby_version']}",
              "Sync #{meta['sync_interval_seconds']}s",
              "Collected #{format_collected meta['collected_at']}"
            ].join " │ "
            Box.new(budget.cols).draw title: title, lines: [line], style: :double
          end

          # @param payload [Hash]
          # @param budget [LayoutBudget]
          # @param refresh_interval [Integer, nil] shown in FOOTER when +--watch+
          # @return [String] SUMMARY, workers, optional FOOTER, and layout warnings
          def render_body payload, budget, refresh_interval: nil
            workers = filtered_workers payload["workers"] || []
            workers = sort_workers workers
            parts = budget.warnings.dup
            parts << render_summary(payload, budget)
            parts.concat render_workers(workers, budget)
            parts << render_footer(refresh_interval) if @options.watch? && refresh_interval
            parts.compact.join "\n\n"
          end

          private

          def filtered_workers workers
            return workers if @options.worker.nil?

            workers.select { |worker| worker["index"].to_i == @options.worker.to_i }
          end

          def sort_workers workers
            key = @options.sort.to_s
            workers.sort_by do |worker|
              puma = worker["puma"] || {}
              process = worker["process"] || {}
              case key
              when "cpu" then [-process["cpu_percent"].to_f, worker["index"].to_i]
              when "rss" then [-process["rss_bytes"].to_i, worker["index"].to_i]
              when "backlog" then [-puma["backlog"].to_i, worker["index"].to_i]
              else [worker["index"].to_i]
              end
            end
          end

          def render_summary payload, budget
            box = Box.new budget.cols
            aggregator = SummaryAggregator.new payload
            bar_width = budget.bar_width
            lines = aggregator.lines.map do |line|
              if line.ratio
                bar, label = @bar.render line.ratio, width: bar_width, backlog: line.backlog
                badge = line.level == :ok ? label : line.level.to_s.upcase
                text = badge unless line.backlog || line.level == :ok
                text ||= format "%3.0f%%", line.ratio * 100
                "#{line.label.ljust(20)} #{line.value.to_s.ljust(12)} [#{bar}] #{text}"
              else
                suffix = line.level == :ok ? "" : " #{line.level.to_s.upcase}"
                "#{line.label.ljust(20)} #{line.value}#{suffix}"
              end
            end
            box.draw title: "SUMMARY", lines: lines
          end

          def render_workers workers, budget
            return [] if workers.empty?

            if budget.compact_grid && workers.size <= 2
              [render_worker_grid(workers, budget)]
            else
              workers.map { |worker| render_worker worker, budget }
            end
          end

          def render_worker_grid workers, budget
            inner = budget.worker_inner_width
            boxes = workers.map { |worker| render_worker(worker, budget, width: inner).split("\n") }
            lines = merge_columns boxes[0], boxes[1], inner, budget.cols
            Box.new(budget.cols).draw title: "WORKERS", lines: lines
          end

          def merge_columns left, right, inner_width, _total_width
            max = [left.size, right.size].max
            gutter = "  "
            (0...max).map do |index|
              l = left[index] || ""
              r = right[index] || ""
              l = l.ljust inner_width
              "#{l}#{gutter}#{r}"
            end
          end

          def render_worker worker, budget, width: nil
            box_width = width || budget.cols
            box = Box.new box_width
            puma = worker["puma"] || {}
            process = worker["process"] || {}
            badge = worker_badge worker
            title = "WORKER #{worker['index']} ─ pid #{worker['pid']}"
            synced = worker["synced_at"] ? Format.rel_time(worker["synced_at"]) : "never"
            title += " ─ #{worker['synced_at'] ? synced : 'not synced'}"
            metrics = worker_metric_lines worker, puma, process, box_width
            items = worker.dig("requests", "items") || []
            table = RequestTable.new items, inner_width: box_width - 4, colors: @colors
            overflow_count = table.overflow_field_count
            max_items = budget.max_requests_for_worker items, overflow_fields: overflow_count
            request_lines = table.render max_items: max_items
            truncated = worker.dig "requests", "meta", "truncated"
            request_badge = truncated ? "[trunc]" : nil
            title_badge = [badge, request_badge].compact.join " "
            box.draw_with_divider title: title, top_lines: metrics, bottom_lines: request_lines,
                                  badge: title_badge.empty? ? nil : title_badge
          end

          def worker_badge worker
            puma = worker["puma"] || {}
            return "[CRIT] not synced" if worker["synced_at"].nil? && (worker["index"] || 0).to_i >= 0

            running = puma["running"].to_i
            max = puma["max_threads"].to_i
            return "[WARN] saturated" if max.positive? && running >= max
            return "[WARN] queue" if puma["backlog"].to_i.positive?

            nil
          end

          def worker_metric_lines worker, puma, process, box_width
            bar_width = [box_width - 28, 8].max
            lines = []
            running = puma["running"].to_i
            max = puma["max_threads"].to_i
            ratio = max.positive? ? running.to_f / max : 0.0
            bar, label = @bar.render ratio, width: bar_width, backlog: false
            lines << metric_line("Threads", "#{running} / #{max}", bar, label)

            capacity = puma["pool_capacity"].to_i
            cap_ratio = max.positive? ? capacity.to_f / max : 0.0
            bar, label = @bar.render cap_ratio, width: bar_width, backlog: false
            lines << metric_line("Capacity", "#{capacity} / #{max}", bar, label)

            backlog = puma["backlog"].to_i
            back_ratio = max.positive? ? backlog.to_f / max : backlog.positive? ? 1.0 : 0.0
            bar, label = @bar.render back_ratio, width: bar_width, backlog: true
            lines << metric_line("Backlog", backlog.to_s, bar, label)

            cpu = process["cpu_percent"]
            if cpu
              bar, label = @bar.render cpu.to_f / 100.0, width: bar_width, backlog: false
              lines << metric_line("CPU", "#{cpu}%", bar, label)
            end

            rss = process["rss_bytes"]
            if rss
              bar, label = @bar.render 0.4, width: bar_width, backlog: false
              lines << metric_line("RSS", Format.bytes(rss), bar, label)
            end

            registry = worker.dig("requests", "meta") || {}
            lines << "Registry  #{registry['count']} / #{registry['request_limit']}  #{registry['limit_policy']}"
            lines
          end

          def metric_line label, value, bar, suffix
            "#{label.ljust(10)} #{value.ljust(12)} [#{bar}] #{suffix}"
          end

          def render_footer refresh_interval
            Box.new(Terminal.cols @options).draw(
              title: "FOOTER",
              lines: [
                "Refresh #{refresh_interval}s (sync_interval) │ Ctrl+C quit │ resize: SIGWINCH redraw"
              ]
            )
          end

          def format_collected value
            return "n/a" if value.nil?

            Time.iso8601(value.to_s).strftime "%H:%M:%S"
          rescue ArgumentError
            value.to_s
          end
        end
      end
    end
  end
end
