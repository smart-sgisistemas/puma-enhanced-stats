# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module CLI
        # Design modal (layout + request display).
        class DesignScreen
          MODES = FrameRenderer::LAYOUTS

          def render(options, budget)
            lines = MODES.map do |mode|
              min = LayoutRegistry::MODES[mode]
              hint = min.positive? ? "needs #{min} cols" : ""
              marker = options.frame_layout == mode ? "[ok]" : ""
              "#{mode.ljust 14} #{marker} #{hint}".strip
            end
            lines += [
              "",
              "request display: #{options.request_display}",
              "cycle with i in dashboard"
            ]
            Box.new(budget.cols).draw(title: "DESIGN", lines: lines)
          end
        end
      end
    end
  end
end
