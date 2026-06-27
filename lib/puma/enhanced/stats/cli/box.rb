# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module CLI
        # Draws Unicode box borders around dashboard sections.
        class Box
          Spec = Struct.new(:title, :lines, :badge, :top_lines, :bottom_lines, keyword_init: true)

          SIMPLE = {
            tl: "┌", tr: "┐", bl: "└", br: "┘", h: "─", v: "│",
            divider_l: "├", divider_r: "┤"
          }.freeze
          DOUBLE = {
            tl: "╔", tr: "╗", bl: "╚", br: "╝", h: "═", v: "║",
            divider_l: "╠", divider_r: "╣"
          }.freeze

          def initialize(max_width, fixed_width: nil)
            @max_width = [max_width, 10].max
            @fixed_width = fixed_width
          end

          def self.unified_width(specs, max_cols)
            specs = Array(specs).compact
            return max_cols if specs.empty?

            width = specs.map { |spec| new(max_cols).needed_width(content_lines(spec), label_for(spec)) }.max
            [[width, 10].max, max_cols].min
          end

          def self.content_lines(spec)
            if spec.top_lines && spec.bottom_lines
              spec.top_lines + spec.bottom_lines
            else
              Array(spec.lines)
            end
          end

          def self.label_for(spec)
            spec.badge ? "#{spec.title} ─ #{spec.badge}" : spec.title.to_s
          end

          def draw(title:, lines:, badge: nil, style: :simple, border_level: nil, colors: nil)
            chars = style == :double ? DOUBLE : SIMPLE
            label = title_label(title, badge)
            @width = resolve_width(lines, label)
            wrapped = wrap_lines(lines)
            top = decorate_border top_border(label, chars), border_level, colors
            body = wrapped.map { |line| content_line line, chars, border_level: border_level, colors: colors }
            bottom = decorate_border bottom_border(chars), border_level, colors
            ([top] + body + [bottom]).join "\n"
          end

          def draw_with_divider(title:, top_lines:, bottom_lines:, badge: nil, border_level: nil, colors: nil)
            chars = SIMPLE
            label = title_label(title, badge)
            all_lines = top_lines + bottom_lines
            @width = resolve_width(all_lines, label)
            wrapped_top = wrap_lines(top_lines)
            wrapped_bottom = wrap_lines(bottom_lines)
            parts = [decorate_border(top_border(label, chars), border_level, colors)]
            wrapped_top.each { |line| parts << content_line(line, chars, border_level: border_level, colors: colors) }
            parts << decorate_border(
              "#{chars[:divider_l]}#{chars[:h] * inner_width}#{chars[:divider_r]}",
              border_level, colors
            )
            wrapped_bottom.each { |line| parts << content_line(line, chars, border_level: border_level, colors: colors) }
            parts << decorate_border(bottom_border(chars), border_level, colors)
            parts.join "\n"
          end

          def needed_width(lines, title)
            fit_width(Array(lines), title)
          end

          private

          def resolve_width(lines, title)
            width = @fixed_width || fit_width(lines, title)
            [[width, 10].max, @max_width].min
          end

          def fit_width(lines, title)
            longest = lines.map { |line| Format.display_length(line) }.max.to_i
            title_need = title.length + 6
            [longest + 3, title_need, 10].max
          end

          def inner_width = @width - 2

          def title_label(title, badge) = badge ? "#{title} ─ #{badge}" : title.to_s

          def bottom_border(chars) = "#{chars[:bl]}#{chars[:h] * inner_width}#{chars[:br]}"

          def top_border(title, chars)
            label = Format.truncate_display("─ #{title} ", inner_width)
            filler = [inner_width - Format.display_length(label), 0].max
            "#{chars[:tl]}#{label}#{chars[:h] * filler}#{chars[:tr]}"
          end

          def content_line(text, chars, border_level: nil, colors: nil)
            slot = inner_width - 1
            inner = Format.pad_right(text.to_s, slot)
            left = colored_border_char(chars[:v], border_level, colors)
            right = colored_border_char(chars[:v], border_level, colors)
            "#{left} #{inner}#{right}"
          end

          def colored_border_char(char, level, colors)
            return char unless colors && level && level != :ok

            colors.paint(char, level)
          end

          def decorate_border(line, level, colors)
            return line unless colors && level && level != :ok

            colors.paint(line, level)
          end

          def wrap_lines(lines)
            slot = inner_width - 1
            Array(lines).flat_map do |line|
              string = line.to_s
              Format.display_length(string) <= slot ? [string] : Format.wrap(string, slot)
            end
          end
        end
      end
    end
  end
end
