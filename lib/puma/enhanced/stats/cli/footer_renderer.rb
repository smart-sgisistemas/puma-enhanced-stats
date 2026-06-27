# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module CLI
        # FOOTER block with key hints.
        class FooterRenderer
          SEGMENT_SEPARATOR = " │ "

          def box_spec(options, budget, refresh_interval:, layout_hint: nil)
            inner = LayoutGrid.content_width(budget.capped_cols)
            layout = layout_hint || "layout: #{options.frame_layout}"
            display = options.request_display == "auto" ? "auto→#{budget.request_display_mode}" : options.request_display
            top = options.top? ? "on" : "off"
            status_segments = [
              "refresh #{refresh_interval}s",
              layout,
              "requests: #{display}",
              "top+proc: #{top}"
            ]
            status_segments.unshift(options.save_message) if options.save_message
            key_segments = [
              "r d l i o f O ? W save",
              "j k wheel [ ] scroll",
              "x clear",
              "0-9 focus",
              "Ctrl+C quit"
            ]
            lines = Format.wrap_segments(status_segments, separator: SEGMENT_SEPARATOR, width: inner)
            lines.concat Format.wrap_segments(key_segments, separator: SEGMENT_SEPARATOR, width: inner)
            Box::Spec.new(title: "FOOTER", lines: lines)
          end

          def render(options, budget, refresh_interval:, layout_hint: nil)
            spec = box_spec options, budget, refresh_interval: refresh_interval, layout_hint: layout_hint
            budget.make_box.draw title: spec.title, lines: spec.lines
          end
        end
      end
    end
  end
end
