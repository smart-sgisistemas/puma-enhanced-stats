# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module CLI
        # Renders Unicode progress bars (+█+ / +░+) with ratio labels.
        #
        # Used in SUMMARY, worker metrics, and {TopRenderer} SYSTEM lines.
        #
        # @see Colors
        class Bar
          # @param colors [Colors]
          def initialize colors
            @colors = colors
          end

          # @param ratio [Numeric] fill level in +0.0..1.0+ (clamped)
          # @param width [Integer] bar width in characters
          # @param backlog [Boolean] use queue/saturated labels instead of percent
          # @return [Array(String, String)] +[bar_string, label]+
          def render ratio, width:, backlog: false
            ratio = ratio.to_f
            ratio = 0.0 if ratio.negative?
            ratio = 1.0 if ratio > 1.0
            filled = (ratio * width).round
            level = @colors.level ratio, backlog: backlog
            bar = @colors.bar_segment(level) * filled
            bar += @colors.empty_segment * (width - filled)
            percent = format "%3.0f%%", ratio * 100
            label = backlog && ratio.positive? ? "queue" : (ratio >= 1.0 ? "saturated" : "ok")
            label = percent if ratio.positive? && !backlog && ratio < 1.0
            label = "ok" if ratio.zero? && !backlog
            [bar, label]
          end
        end
      end
    end
  end
end
