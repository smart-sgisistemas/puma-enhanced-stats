# frozen_string_literal: true

require_relative "box"
require_relative "format"
require_relative "summary_aggregator"
require_relative "request_table"
require_relative "worker_list"

module Puma
  module Enhanced
    module Stats
      module CLI
        # Renders HEADER, SUMMARY, WORKER boxes, and optional FOOTER.
        class DashboardRenderer
          def initialize(options, bar) = (@options = options; @bar = bar)

          def render_header payload, budget
            meta = payload["meta"] || {}
            title = "PUMA ENHANCED STATS ─ v#{meta['gem_version'] || VERSION}"
            line = [
              "Mode #{meta['mode']}",
              "Puma #{meta['puma_version']}",
              "Ruby #{meta['ruby_version']}",
              "Sync #{meta['worker_check_interval_seconds']}s",
              "Collected #{format_collected meta['collected_at']}"
            ].join " │ "
            Box.new(budget.cols).draw title: title, lines: [line], style: :double
          end

          def render_body payload, budget, refresh_interval: nil
            workers = WorkerList.prepare payload["workers"] || [], @options
            parts = budget.warnings.dup
            parts << render_summary(payload, budget)
            parts.concat render_workers(workers, budget)
            parts << render_footer(refresh_interval, budget.cols) if @options.watch && refresh_interval
            parts.compact.join "\n\n"
          end

          private

          def render_summary payload, budget
            box = Box.new budget.cols
            bar_width = budget.bar_width
            lines = SummaryAggregator.new(payload).lines.map do |line|
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
            lines = merge_columns boxes[0], boxes[1], inner
            Box.new(budget.cols).draw title: "WORKERS", lines: lines
          end

          def merge_columns left, right, inner_width
            max = [left.size, right.size].max
            (0...max).map do |index|
              l = (left[index] || "").ljust(inner_width)
              "#{l}  #{right[index] || ""}"
            end
          end

          def render_worker worker, budget, width: nil
            box_width = width || budget.cols
            puma = worker["puma"] || {}
            process = worker["process"] || {}
            synced = worker["synced_at"] ? Format.rel_time(worker["synced_at"]) : "not synced"
            title = "WORKER #{worker['index']} ─ pid #{worker['pid']} ─ #{synced}"
            table = RequestTable.new worker.dig("requests", "items") || [], inner_width: box_width - 4
            overflow_count = table.overflow_field_count
            max_items = budget.max_requests_for_worker table.instance_variable_get(:@items),
                                                         overflow_fields: overflow_count
            request_lines = table.render max_items: max_items
            truncated = worker.dig("requests", "meta", "truncated")
            title_badge = [worker_badge(worker), truncated ? "[trunc]" : nil].compact.join " "
            box = Box.new box_width
            box.draw_with_divider title: title,
                                  top_lines: worker_metric_lines(puma, process, box_width, worker),
                                  bottom_lines: request_lines,
                                  badge: title_badge.empty? ? nil : title_badge
          end

          def worker_badge worker
            puma = worker["puma"] || {}
            return "[CRIT] not synced" unless worker["synced_at"] || worker["index"].to_i.negative?

            running = puma["running"].to_i
            max = puma["max_threads"].to_i
            return "[WARN] saturated" if max.positive? && running >= max
            return "[WARN] queue" if puma["backlog"].to_i.positive?

            nil
          end

          def worker_metric_lines puma, process, box_width, worker
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

            if (cpu = process["cpu_percent"])
              bar, label = @bar.render cpu.to_f / 100.0, width: bar_width, backlog: false
              lines << metric_line("CPU", "#{cpu}%", bar, label)
            end

            if (rss = process["rss_bytes"])
              bar, label = @bar.render 0.4, width: bar_width, backlog: false
              lines << metric_line("RSS", Format.bytes(rss), bar, label)
            end

            registry = worker.dig("requests", "meta") || {}
            lines << "Registry  #{registry['count']} / #{registry['request_limit']}  #{registry['limit_policy']}"
            lines
          end

          def metric_line(label, value, bar, suffix) = "#{label.ljust(10)} #{value.ljust(12)} [#{bar}] #{suffix}"

          def render_footer refresh_interval, cols
            Box.new(cols).draw(
              title: "FOOTER",
              lines: [
                "Refresh #{refresh_interval}s (worker_check_interval) │ Ctrl+C quit │ resize: SIGWINCH redraw"
              ]
            )
          end

          def format_collected value
            return "n/a" unless value

            Time.iso8601(value.to_s).strftime "%H:%M:%S"
          rescue ArgumentError
            value.to_s
          end
        end
      end
    end
  end
end
