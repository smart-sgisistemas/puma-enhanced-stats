# frozen_string_literal: true

require "socket"
require "time"

module Puma
  module Enhanced
    module Stats
      module CLI
        # String formatting helpers shared by CLI renderers.
        module Format
          ANSI_PATTERN = /\e\[[0-9;]*m/.freeze

          module_function

          def strip_ansi(text)
            text.to_s.gsub(ANSI_PATTERN, "")
          end

          def display_length(text)
            strip_ansi(text).length
          end

          def pad_right(text, width)
            string = text.to_s
            visible = display_length(string)
            if visible > width
              truncate_display(string, width)
            elsif visible < width
              padded = string.include?("\e") ? "#{string}\e[0m" : string
              "#{padded}#{' ' * (width - visible)}"
            elsif string.include?("\e")
              "#{string}\e[0m"
            else
              string
            end
          end

          def truncate_display(text, max_width)
            return "" if max_width <= 0

            string = text.to_s
            return string if display_length(string) <= max_width

            out = +""
            visible = 0
            index = 0
            while index < string.length && visible < max_width
              if string[index] == "\e"
                close = string.index("m", index)
                break unless close

                out << string[index..close]
                index = close + 1
                next
              end

              out << string[index]
              visible += 1
              index += 1
            end
            out << "\e[0m" if string.include?("\e")
            out
          end

          def center_display(text, width)
            return "" if width <= 0

            string = text.to_s
            visible = display_length(string)
            return truncate_display(string, width) if visible > width

            left = (width - visible) / 2
            right = width - visible - left
            "#{' ' * left}#{string}#{' ' * right}"
          end

          def cols_label(count)
            count = count.to_i
            count == 1 ? "1 COL" : "#{count} COLS"
          end

          def wrap_segments(segments, separator:, width:)
            parts = Array(segments).map(&:to_s).reject(&:empty?)
            return [""] if parts.empty?

            lines = []
            current = nil

            parts.each do |segment|
              if current.nil?
                current = segment
                next
              end

              candidate = "#{current}#{separator}#{segment}"
              if display_length(candidate) <= width
                current = candidate
              else
                lines << current
                if display_length(segment) > width
                  lines.concat(wrap(segment, width))
                  current = nil
                else
                  current = segment
                end
              end
            end

            lines << current if current
            lines
          end

          def wrap(text, width)
            wrap_indented("", text.to_s, width)
          end

          def wrap_indented(prefix, text, width)
            string = text.to_s
            prefix_len = display_length(prefix)
            return [prefix] if width <= prefix_len

            lines = []
            index = 0
            current_prefix = prefix

            while index < string.length
              room = width - display_length(current_prefix)
              room = 1 if room < 1
              chunk, index = take_display(string, index, room)
              lines << "#{current_prefix}#{chunk}"
              current_prefix = " " * prefix_len
            end

            lines = [prefix] if lines.empty?
            lines
          end

          def take_display(string, start_index, max_width)
            out = +""
            visible = 0
            index = start_index
            while index < string.length && visible < max_width
              if string[index] == "\e"
                close = string.index("m", index)
                break unless close

                out << string[index..close]
                index = close + 1
                next
              end

              out << string[index]
              visible += 1
              index += 1
            end
            out << "\e[0m" if out.include?("\e")
            [out, index]
          end

          def truncate(text, max_width)
            string = text.to_s
            return string if string.length <= max_width
            return "" if max_width <= 1

            "#{string[0, max_width - 1]}…"
          end

          def bytes(size)
            return "n/a" unless size.is_a? Integer

            size = size.to_i
            if size >= 1_073_741_824
              format "%.1f GiB", size / 1_073_741_824.0
            elsif size >= 1_048_576
              format "%.0f MiB", size / 1_048_576.0
            elsif size >= 1024
              format "%.0f KiB", size / 1024.0
            else
              "#{size} B"
            end
          end

          def elapsed(collected_at, started_at, now: Time.now)
            return "n/a" if started_at.to_s.empty?

            started = Time.iso8601(started_at.to_s)
            reference = collected_at.to_s.empty? ? now : Time.iso8601(collected_at.to_s)
            seconds = (reference - started).to_f
            return format "%.1fs", seconds if seconds < 60
            return format "%dm %ds", seconds / 60, seconds % 60 if seconds < 3600

            format "%dh %dm", seconds / 3600,  seconds % 3600 / 60
          rescue ArgumentError
            "n/a"
          end

          def elapsed_ms(ms)
            return "n/a" unless ms.is_a? Integer

            seconds = ms.to_f / 1000
            return format "%.1fs", seconds if seconds < 60

            format "%.1fm", seconds / 60
          end

          def rel_time(iso8601, now: Time.now)
            return "never" if iso8601.to_s.empty?

            started = Time.iso8601(iso8601.to_s)
            delta = (now - started).to_i
            return "#{delta}s ago" if delta < 60

            "#{delta / 60}m ago"
          rescue ArgumentError
            "n/a"
          end

          def hostname
            Socket.gethostname
          rescue StandardError
            "localhost"
          end

          def table_row(columns, widths)
            columns.each_with_index.map { |value, index| pad_right(value, widths[index]) }.join "  "
          end

          def column_widths(rows)
            widths = []
            rows.each do |row|
              row.each_with_index do |cell, index|
                widths[index] = [widths[index].to_i, display_length(cell)].max
              end
            end
            widths
          end

          def collected_clock(value)
            return "n/a" unless value

            Time.iso8601(value.to_s).strftime "%H:%M:%S"
          rescue ArgumentError
            value.to_s
          end
        end
      end
    end
  end
end
