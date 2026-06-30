# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module CLI
        # SUMMARY block — cluster aggregates vs single pool counters (+ optional Host vs Puma).
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
            view = PayloadView.wrap(payload)
            content_width = budget.metric_content_width
            lines = view.cluster? ? cluster_lines(view) : single_lines(view)
            if attribution.show_summary_line?
              lines << label("Host vs Puma", attribution.summary_value, badge: attribution.level)
            end
            lines.flat_map { |line| line.render(content_width: content_width) }
          end

          def cluster_lines(view)
            max_threads = view.max_threads_total
            reporting = view.workers_reporting
            total_workers = view.workers_total
            sync_status = workers_sync_status(view)

            [
              metric(
                "Workers reporting", "#{reporting} / #{total_workers}",
                ratio: total_workers.positive? ? reporting.to_f / total_workers : 0.0,
                suffix: sync_status[:suffix],
                bar_level: sync_status[:level]
              ),
              metric(
                "Requests in flight", "#{view.requests_in_flight} / #{max_threads}",
                ratio: max_threads.positive? ? view.requests_in_flight.to_f / max_threads : 0.0
              ),
              metric(
                "Backlog total", "#{view.backlog_total} / #{max_threads}",
                ratio: max_threads.positive? ? view.backlog_total.to_f / max_threads : 0.0,
                backlog: true
              ),
              metric(
                "Busy threads", "#{view.busy_threads_total} / #{max_threads}",
                ratio: max_threads.positive? ? view.busy_threads_total.to_f / max_threads : 0.0
              ),
              metric(
                "Pool capacity", "#{view.pool_capacity_total} / #{max_threads}",
                ratio: max_threads.positive? ? view.pool_capacity_total.to_f / max_threads : 0.0
              )
            ]
          end

          def single_lines(view)
            max_threads = view.max_threads_total

            [
              metric(
                "Requests in flight", "#{view.requests_in_flight} / #{max_threads}",
                ratio: max_threads.positive? ? view.requests_in_flight.to_f / max_threads : 0.0
              ),
              metric(
                "Backlog", "#{view.backlog_total} / #{max_threads}",
                ratio: max_threads.positive? ? view.backlog_total.to_f / max_threads : 0.0,
                backlog: true
              ),
              metric(
                "Running", "#{view.running_total} / #{max_threads}",
                ratio: max_threads.positive? ? view.running_total.to_f / max_threads : 0.0
              ),
              metric(
                "Busy threads", "#{view.busy_threads_total} / #{max_threads}",
                ratio: max_threads.positive? ? view.busy_threads_total.to_f / max_threads : 0.0
              ),
              metric(
                "Pool capacity", "#{view.pool_capacity_total} / #{max_threads}",
                ratio: max_threads.positive? ? view.pool_capacity_total.to_f / max_threads : 0.0
              )
            ]
          end

          def metric(label, value, ratio:, suffix: nil, bar_level: nil, backlog: false)
            auto_suffix = @bar.suffix_label(ratio, backlog: backlog)
            MetricLine.new(
              label: label, value: value,
              suffix: suffix.nil? ? auto_suffix : suffix, colors: @colors,
              ratio: ratio, bar_renderer: @bar, backlog: backlog, bar_level: bar_level
            )
          end

          def workers_sync_status(view)
            interval = view.worker_check_interval_seconds
            interval = PayloadView::DEFAULT_SYNC_INTERVAL if interval <= 0
            AlertLevel.aggregate_worker_sync(
              view.workers,
              collected_at: view.collected_at,
              interval_seconds: interval,
              mode: view.mode
            )
          end

          def label(label, value, badge:)
            LabelLine.new(label: label, value: value, badge: badge, colors: @colors)
          end
        end
      end
    end
  end
end
