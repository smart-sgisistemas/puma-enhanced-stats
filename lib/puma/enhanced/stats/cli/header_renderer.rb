# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module CLI
        # HEADER block renderer.
        class HeaderRenderer
          SEGMENT_SEPARATOR = " │ "

          def box_spec(payload, budget:)
            meta = payload["meta"] || {}
            version = meta["gem_version"] || Stats::VERSION
            title = "PUMA ENHANCED STATS ─ v#{version}"
            lines = meta_lines(meta, budget)
            Box::Spec.new(title: title, lines: lines)
          end

          def render(payload, budget)
            spec = box_spec payload, budget: budget
            budget.make_box.draw title: spec.title, lines: spec.lines
          end

          private

          def meta_lines(meta, budget)
            segments = [
              meta["mode"],
              "sync #{meta['worker_check_interval_seconds']}s",
              "collected #{Format.collected_clock meta['collected_at']}",
              Format.cols_label(budget.cols)
            ]
            Format.wrap_segments(
              segments,
              separator: SEGMENT_SEPARATOR,
              width: LayoutGrid.content_width(budget.capped_cols)
            )
          end
        end
      end
    end
  end
end
