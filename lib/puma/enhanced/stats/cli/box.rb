# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module CLI
        # Draws Unicode box borders around dashboard sections.
        class Box
          SIMPLE = {
            tl: "┌", tr: "┐", bl: "└", br: "┘", h: "─", v: "│",
            divider_l: "├", divider_r: "┤"
          }.freeze

          DOUBLE = {
            tl: "╔", tr: "╗", bl: "╚", br: "╝", h: "═", v: "║",
            divider_l: "╠", divider_r: "╣"
          }.freeze

          # @param width [Integer] outer box width (minimum 10)
          # @return [Box]
          def initialize(width) = @width = [width, 10].max

          # @param title [String]
          # @param lines [Array<String>]
          # @param style [Symbol] +:simple+ or +:double+
          # @param badge [String, nil]
          # @return [String]
          def draw title:, lines:, style: :simple, badge: nil
            chars = style == :double ? DOUBLE : SIMPLE
            top = top_border title_label(title, badge), chars
            body = lines.map { |line| content_line(line, chars) }
            ([top] + body + [bottom_border(chars)]).join "\n"
          end

          # @param title [String]
          # @param top_lines [Array<String>]
          # @param bottom_lines [Array<String>]
          # @param badge [String, nil]
          # @return [String]
          def draw_with_divider title:, top_lines:, bottom_lines:, badge: nil
            chars = SIMPLE
            parts = [top_border(title_label(title, badge), chars)]
            top_lines.each { |line| parts << content_line(line, chars) }
            parts << "#{chars[:divider_l]}#{chars[:h] * inner_width}#{chars[:divider_r]}"
            bottom_lines.each { |line| parts << content_line(line, chars) }
            parts << bottom_border(chars)
            parts.join "\n"
          end

          private

          def inner_width = @width - 2

          def title_label(title, badge) = badge ? "#{title} ─ #{badge}" : title.to_s

          def bottom_border(chars) = "#{chars[:bl]}#{chars[:h] * inner_width}#{chars[:br]}"

          def top_border title, chars
            label = "─ #{title} "
            remaining = [inner_width - label.length, 1].max
            "#{chars[:tl]}#{label}#{chars[:h] * remaining}#{chars[:tr]}"
          end

          def content_line text, chars
            inner = Format.truncate text.to_s, @width - 4
            "#{chars[:v]} #{inner.ljust(inner_width - 1)}#{chars[:v]}"
          end
        end
      end
    end
  end
end
