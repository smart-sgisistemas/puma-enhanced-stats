# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module CLI
        # Renders a fixed-width progress bar with a text label.
        class Bar
          BAR_WIDTH = 20

          def initialize(colors) = @colors = colors

          def render(ratio, width: BAR_WIDTH, backlog: false, level: nil)
            ratio = ratio.to_f.clamp(0.0, 1.0)
            filled = (ratio * width).round
            level ||= @colors.level(ratio, backlog: backlog)
            bar = @colors.paint("█", level) * filled
            bar += @colors.paint("░", :muted) * (width - filled)
            bar += "\e[0m" if @colors.enabled?
            [bar, suffix_for(ratio, level, backlog: backlog)]
          end

          def suffix_label(ratio, backlog: false)
            level = @colors.level(ratio, backlog: backlog)
            suffix_for(ratio, level, backlog: backlog)
          end

          private

          def suffix_for(ratio, level, backlog:)
            return "queue" if backlog && ratio.positive?
            return "saturated" if level == :crit && ratio >= 1.0
            return "ok" if level == :ok && ratio.zero?

            return @colors.badge(level) unless level == :ok

            format "%3.0f%%", ratio * 100
          end
        end
      end
    end
  end
end
