# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module CLI
        # HEADER block renderer.
        class HeaderRenderer
          SEGMENT_SEPARATOR = " │ "

          def box_spec(payload, budget:)
            view = PayloadView.wrap(payload)
            title = "PUMA ENHANCED STATS ─ v#{view.gem_version}"
            lines = meta_lines(view, budget)
            Box::Spec.new(title: title, lines: lines)
          end

          def render(payload, budget)
            spec = box_spec payload, budget: budget
            budget.make_box.draw title: spec.title, lines: spec.lines
          end

          private

          def meta_lines(view, budget)
            interval = view.worker_check_interval_seconds
            sync_label = view.single? ? "live" : "sync #{interval}s"
            segments = [view.mode]
            if view.cluster?
              segments << "workers #{view.raw['workers']}"
              segments << "phase #{view.raw['phase']}"
            end
            segments << sync_label
            segments << "collected #{Format.collected_clock view.collected_at}"
            segments << Format.cols_label(budget.cols)
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
