# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module CLI
        # Renders a fixed-width progress bar with a text label.
        #
        # Ratios are clamped to +0.0..1.0+. Returns +[bar_string, label]+.
        class Bar
          def initialize(colors) = @colors = colors

          def render ratio, width:, backlog: false
            ratio = ratio.to_f.clamp(0.0, 1.0)
            filled = (ratio * width).round
            level = @colors.level ratio, backlog: backlog
            bar = @colors.paint("█", level) * filled
            bar += @colors.paint("░", :muted) * (width - filled)
            [bar, label_for(ratio, backlog: backlog)]
          end

          private

          def label_for ratio, backlog:
            return "queue" if backlog && ratio.positive?
            return "saturated" if ratio >= 1.0
            return "ok" if ratio.zero?

            format "%3.0f%%", ratio * 100
          end
        end
      end
    end
  end
end
