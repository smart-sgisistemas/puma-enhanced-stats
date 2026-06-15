# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module CLI
        # Draws bordered Unicode boxes for dashboard sections.
        #
        # Used by {DashboardRenderer} (HEADER, SUMMARY, WORKER, FOOTER) and
        # {TopRenderer} (SYSTEM, PROCESSES).
        #
        # @see Format#pad_line
        class Box
          # Single-line border characters.
          SIMPLE = {
            tl: "┌", tr: "┐", bl: "└", br: "┘", h: "─", v: "│",
            divider_l: "├", divider_r: "┤"
          }.freeze

          # Double-line border characters (HEADER).
          DOUBLE = {
            tl: "╔", tr: "╗", bl: "╚", br: "╝", h: "═", v: "║",
            divider_l: "╠", divider_r: "╣"
          }.freeze

          # @param width [Integer] outer box width in columns (minimum 10)
          def initialize width
            @width = [width, 10].max
          end

          # @param title [String] box title shown on the top border
          # @param lines [Array<String>] body lines
          # @param style [Symbol] +:simple+ or +:double+
          # @param badge [String, nil] optional suffix appended to the title
          # @return [String] multi-line box
          def draw title:, lines:, style: :simple, badge: nil
            chars = style == :double ? DOUBLE : SIMPLE
            title_text = title.to_s
            title_text += " ─ #{badge}" if badge
            top = top_border title_text, chars
            body = lines.map { |line| content_line(line, chars) }
            bottom = "#{chars[:bl]}#{chars[:h] * inner_width}#{chars[:br]}"
            ([top] + body + [bottom]).join "\n"
          end

          # Worker box with a horizontal divider between metrics and in-flight table.
          #
          # @param title [String]
          # @param top_lines [Array<String>] metrics above the divider
          # @param bottom_lines [Array<String>] request table below the divider
          # @param badge [String, nil]
          # @return [String]
          def draw_with_divider title:, top_lines:, bottom_lines:, badge: nil
            chars = SIMPLE
            title_text = badge ? "#{title} ─ #{badge}" : title.to_s
            parts = [top_border(title_text, chars)]
            top_lines.each { |line| parts << content_line(line, chars) }
            parts << "#{chars[:divider_l]}#{chars[:h] * inner_width}#{chars[:divider_r]}"
            bottom_lines.each { |line| parts << content_line(line, chars) }
            parts << "#{chars[:bl]}#{chars[:h] * inner_width}#{chars[:br]}"
            parts.join "\n"
          end

          private

          def inner_width = @width - 2

          def top_border title, chars
            label = "─ #{title} "
            remaining = inner_width - label.length
            remaining = 1 if remaining < 1
            "#{chars[:tl]}#{label}#{chars[:h] * remaining}#{chars[:tr]}"
          end

          def content_line text, chars
            inner = Format.pad_line text.to_s, @width
            "#{chars[:v]} #{inner.ljust(inner_width - 1)}#{chars[:v]}"
          end
        end
      end
    end
  end
end
