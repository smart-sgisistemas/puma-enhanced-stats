# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module CLI
        # Worker (cluster) or server (single) box renderer.
        class WorkerRenderer
          def initialize(options, bar, colors)
            @options = options
            @bar = bar
            @colors = colors
          end

          def box_spec(worker, budget, process_by_pid:, collected_at:, interval:, mode:, scroll:, inner_width: nil)
            puma = worker["puma"] || {}
            sample = process_by_pid[worker["pid"]]
            mem_total = ProcessSampler.memory_capacity_bytes || 1
            max = puma["max_threads"].to_i
            single = worker["single"] || mode == "single"
            sync = SyncFreshness.evaluate(
              synced_at: worker["synced_at"],
              collected_at: collected_at,
              interval_seconds: interval,
              mode: mode
            )

            title = box_title(worker, sync, single: single)
            badge = worker_title_badge(puma, sync, single: single)
            top_lines = worker_metrics(puma, sample, max, mem_total, sync, worker, single: single)
            items = RequestPipeline.process(
              worker.dig("requests", "items") || [],
              collected_at: collected_at,
              options: @options
            )
            offset = scroll.request_offset_for worker["index"]
            table_width = inner_width || budget.cols - 4
            table = RequestTable.new(
              items,
              inner_width: table_width,
              display_mode: budget.request_display_mode,
              offset: offset
            )
            max_items = budget.max_requests_for_worker items, overflow_fields: table.overflow_field_count
            request_lines = table.render max_items: max_items

            content_width = budget.metric_content_width(budget.worker_box_cols)
            rendered_top = top_lines.flat_map do |line|
              line.respond_to?(:render) ? line.render(content_width: content_width) : [line.to_s]
            end
            Box::Spec.new(
              title: title, lines: rendered_top + request_lines, badge: badge,
              top_lines: rendered_top, bottom_lines: request_lines
            )
          end

          def render(worker, budget, process_by_pid:, collected_at:, interval:, mode:, scroll:)
            puma = worker["puma"] || {}
            single = worker["single"] || mode == "single"
            sync = SyncFreshness.evaluate(
              synced_at: worker["synced_at"],
              collected_at: collected_at,
              interval_seconds: interval,
              mode: mode
            )
            spec = box_spec worker, budget, process_by_pid: process_by_pid,
                            collected_at: collected_at, interval: interval, mode: mode, scroll: scroll,
                            inner_width: budget.worker_box_cols - 4

            budget.make_box(fixed_width: budget.worker_box_cols).draw_with_divider(
              title: spec.title,
              top_lines: spec.top_lines,
              bottom_lines: spec.bottom_lines,
              badge: spec.badge,
              border_level: worker_border_level(puma, sync, single: single),
              colors: @colors
            )
          end

          private

          def box_title(worker, sync, single:)
            if single
              pid = worker["pid"]
              pid_label = pid ? "pid #{pid} ─ " : ""
              "SERVER ─ #{pid_label}live read"
            else
              "WORKER #{worker['index']} ─ pid #{worker['pid']} ─ #{sync.title_fragment}"
            end
          end

          def worker_border_level(puma, sync, single:)
            return :crit if puma["backlog"].to_i.positive?
            return :ok if single

            sync.badge
          end

          def worker_title_badge(puma, sync, single:)
            return "[CRIT] backlog #{puma['backlog']}" if puma["backlog"].to_i.positive?
            return nil if single || sync.badge == :ok

            sync.badge.to_s.upcase
          end

          def worker_metrics(puma, sample, max, mem_total, sync, worker, single:)
            lines = []
            unless single
              lines << LabelLine.new(
                label: "checkin",
                value: Format.rel_time(worker["synced_at"]),
                badge: sync.badge,
                colors: @colors
              )
            end
            lines << metric_line("backlog", puma["backlog"], max, backlog: true)
            lines << metric_line("running", puma["running"], max)
            lines << metric_line("pool_capacity", puma["pool_capacity"], max)
            lines << metric_line("busy_threads", puma["busy_threads"], max)
            if sample&.rss_bytes
              lines << metric_line_bytes("rss", sample.rss_bytes, mem_total)
            end
            if sample&.cpu_percent
              lines << metric_line("cpu", sample.cpu_percent, 100, percent: true)
            end
            lines
          end

          def metric_line(label, numerator, denominator, backlog: false, percent: false)
            num = numerator.to_i
            den = denominator.to_i
            ratio = if percent
                      num / 100.0
                    elsif den.positive?
                      num.to_f / den
                    else
                      0.0
                    end
            value = percent ? "#{num} / 100%" : "#{num} / #{den}"
            level = backlog ? AlertLevel.for_backlog(num) : AlertLevel.for_ratio(ratio)
            MetricLine.new(
              label: label, value: value, suffix: level, colors: @colors,
              ratio: ratio, bar_renderer: @bar, backlog: backlog
            )
          end

          def metric_line_bytes(label, bytes, total)
            ratio = total.positive? ? bytes.to_f / total : 0.0
            MetricLine.new(
              label: label,
              value: "#{Format.bytes bytes} / #{Format.bytes total}",
              suffix: format("%3.0f%%", ratio * 100),
              colors: @colors,
              ratio: ratio, bar_renderer: @bar
            )
          end
        end
      end
    end
  end
end
