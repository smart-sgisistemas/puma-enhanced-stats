# frozen_string_literal: true

require "socket"
require "time"

module Puma
  module Enhanced
    module Stats
      module CLI
        # String formatting helpers shared by CLI renderers.
        module Format
          module_function

          # @param text [Object]
          # @param max_width [Integer]
          # @return [String]
          def truncate text, max_width
            string = text.to_s
            return string if string.length <= max_width

            return "" if max_width <= 1

            "#{string[0, max_width - 1]}…"
          end

          # @param size [Integer, nil]
          # @return [String]
          def bytes size
            return "n/a" unless size.is_a?(Integer)

            size = size.to_i
            if size >= 1_073_741_824
              format("%.1f GiB", size / 1_073_741_824.0)
            elsif size >= 1_048_576
              format("%.0f MiB", size / 1_048_576.0)
            elsif size >= 1024
              format("%.0f KiB", size / 1024.0)
            else
              "#{size} B"
            end
          end

          # @param ms [Integer, nil]
          # @return [String]
          def elapsed_ms ms
            return "n/a" unless ms.is_a?(Integer)

            seconds = ms.to_f / 1000
            return format("%.1fs", seconds) if seconds < 60

            format("%.1fm", seconds / 60)
          end

          # @param iso8601 [String]
          # @param now [Time]
          # @return [String]
          def rel_time iso8601, now: Time.now
            return "never" if iso8601.to_s.empty?

            started = Time.iso8601 iso8601.to_s
            delta = (now - started).to_i
            return "#{delta}s ago" if delta < 60

            "#{delta / 60}m ago"
          rescue ArgumentError
            "n/a"
          end

          # @return [String]
          def hostname
            Socket.gethostname
          rescue StandardError
            "localhost"
          end

          # @param columns [Array<Object>]
          # @param widths [Array<Integer>]
          # @return [String]
          def table_row(columns, widths) = columns.each_with_index.map { |value, index| value.to_s.ljust(widths[index]) }.join("  ")

          # @param rows [Array<Array<Object>>]
          # @return [Array<Integer>]
          def column_widths rows
            widths = []
            rows.each do |row|
              row.each_with_index do |cell, index|
                widths[index] = [widths[index].to_i, cell.to_s.length].max
              end
            end
            widths
          end
        end
      end
    end
  end
end
