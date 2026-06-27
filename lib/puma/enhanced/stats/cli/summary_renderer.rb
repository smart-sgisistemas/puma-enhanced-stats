# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module CLI
        # SUMMARY block — exactly 7 MetricLine/LabelLine rows (+ optional Host vs Puma).
        class SummaryRenderer
          def initialize(bar, colors)
            @bar = bar
            @colors = colors
          end

          def box_spec(payload, attribution:, budget:)
            Box::Spec.new(title: "SUMMARY", lines: summary_lines(payload, attribution, budget))
          end

          def render(payload, budget, attribution:)
            spec = box_spec payload, attribution: attribution, budget: budget
            budget.make_box.draw title: spec.title, lines: spec.lines
          end

          private

          def summary_lines(payload, attribution, budget)
            content_width = budget.metric_content_width
            summary = payload["summary"] || {}
            max_threads = summary["max_threads_total"].to_i
            request_limit = request_limit_total payload
            reporting = summary["workers_reporting"].to_i
            total_workers = summary["workers_total"].to_i
            sync_status = workers_sync_status payload

            lines = []
            lines << metric(
              "Workers reporting", "#{reporting} / #{total_workers}",
              ratio: total_workers.positive? ? reporting.to_f / total_workers : 0.0,
              suffix: sync_status[:suffix],
              bar_level: sync_status[:level]
            )
            lines << metric(
              "Requests in flight", "#{summary['requests_in_flight']} / #{request_limit}",
              ratio: request_limit.positive? ? summary["requests_in_flight"].to_f / request_limit : 0.0
            )
            lines << label("Requests dropped", summary["requests_dropped_total"].to_s,
                           badge: AlertLevel.for_dropped(summary["requests_dropped_total"]))
            truncated = summary["requests_truncated"]
            lines << label("Requests truncated", truncated ? "yes" : "no",
                           badge: truncated ? :info : :ok)
            lines << metric(
              "Backlog total", "#{summary['backlog_total']} / #{max_threads}",
              ratio: max_threads.positive? ? summary["backlog_total"].to_f / max_threads : 0.0,
              backlog: true
            )
            lines << metric(
              "Busy threads", "#{summary['busy_threads_total']} / #{max_threads}",
              ratio: max_threads.positive? ? summary["busy_threads_total"].to_f / max_threads : 0.0
            )
            lines << metric(
              "Pool capacity", "#{summary['pool_capacity_total']} / #{max_threads}",
              ratio: max_threads.positive? ? summary["pool_capacity_total"].to_f / max_threads : 0.0
            )
            if attribution.show_summary_line?
              lines << label("Host vs Puma", attribution.summary_value, badge: attribution.level)
            end
            lines.flat_map { |line| line.render(content_width: content_width) }
          end

          def request_limit_total(payload)
            Array(payload["workers"]).sum { |w| w.dig("requests", "meta", "request_limit").to_i }
          end

          def metric(label, value, ratio:, suffix: nil, bar_level: nil, backlog: false)
            auto_suffix = @bar.suffix_label(ratio, backlog: backlog)
            MetricLine.new(
              label: label, value: value,
              suffix: suffix.nil? ? auto_suffix : suffix, colors: @colors,
              ratio: ratio, bar_renderer: @bar, backlog: backlog, bar_level: bar_level
            )
          end

          def workers_sync_status(payload)
            meta = payload["meta"] || {}
            interval = meta["worker_check_interval_seconds"].to_i
            interval = 5 if interval <= 0
            AlertLevel.aggregate_worker_sync(
              payload["workers"],
              collected_at: meta["collected_at"],
              interval_seconds: interval,
              mode: meta["mode"]
            )
          end

          def label(label, value, badge:)
            LabelLine.new(label: label, value: value, badge: badge, colors: @colors)
          end

          def compose_suffix(extra, level, auto)
            return auto.to_s if extra.nil? || extra.to_s.empty?
            return extra if extra.is_a?(String) && extra.include?("\e")

            if extra.is_a?(String)
              begin
                sym = extra.to_sym
                return @colors.badge(sym) if @colors && %i[ok warn crit info degraded].include?(sym)
              rescue StandardError
                # custom text suffixes use the alert level badge
              end
              return @colors ? @colors.badge(level) : level.to_s.upcase
            end

            @colors ? @colors.badge(level) : level.to_s.upcase
          end
        end
      end
    end
  end
end
