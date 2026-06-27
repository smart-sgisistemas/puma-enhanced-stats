# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module CLI
        # OUTSIDE PUMA panel (top 3 outsiders by CPU).
        class OutsidersRenderer
          def box_spec(attribution)
            outsiders = attribution.outsiders
            return nil if outsiders.empty?

            lines = outsiders.map do |row|
              format(
                "%5d  %5.1f  %4.1f  %6s  %s",
                row.pid, row.cpu_percent, row.mem_percent, Format.bytes(row.rss_bytes), row.command
              )
            end
            Box::Spec.new(title: "OUTSIDE PUMA ─ top 3 by cpu ─ press O hide", lines: lines)
          end

          def render(attribution, budget)
            spec = box_spec attribution
            return nil unless spec

            budget.make_box.draw title: spec.title, lines: spec.lines
          end
        end
      end
    end
  end
end
