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

          # Truncates text with an ellipsis when it exceeds +max_width+.
          #
          # @param text [Object]
          # @param max_width [Integer]
          # @return [String]
          def truncate text, max_width
            string = text.to_s
            return string if string.length <= max_width

            return "" if max_width <= 1

            "#{string[0, max_width - 1]}…"
          end

          # Formats byte counts as B/KiB/MiB/GiB.
          #
          # @param size [Integer, nil]
          # @return [String]
          def bytes size
            return "n/a" if size.nil?

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

          # Formats elapsed milliseconds as seconds or minutes.
          #
          # @param ms [Integer, nil]
          # @return [String]
          def elapsed_ms ms
            return "n/a" if ms.nil?

            seconds = ms.to_f / 1000
            return format("%.1fs", seconds) if seconds < 60

            format("%.1fm", seconds / 60)
          end

          # Relative time since an ISO8601 timestamp.
          #
          # @param iso8601 [String, nil]
          # @param now [Time]
          # @return [String]
          def rel_time iso8601, now: Time.now
            return "never" if iso8601.nil? || iso8601.to_s.empty?

            started = Time.iso8601 iso8601.to_s
            delta = (now - started).to_i
            return "#{delta}s ago" if delta < 60

            "#{delta / 60}m ago"
          rescue ArgumentError
            "n/a"
          end

          # @return [String] local hostname or +"localhost"+
          def hostname
            Socket.gethostname
          rescue StandardError
            "localhost"
          end

          # Left-justifies columns and joins with double spaces.
          #
          # @param columns [Array]
          # @param widths [Array<Integer>]
          # @return [String]
          def table_row columns, widths
            columns.each_with_index.map { |value, index| value.to_s.ljust(widths[index]) }.join "  "
          end

          # Computes per-column max width from one or more rows.
          #
          # @param rows [Array<Array>]
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

          # Truncates content to fit inside a {Box} inner line.
          #
          # @param content [String]
          # @param width [Integer] outer box width
          # @return [String]
          def pad_line content, width
            inner = width - 4
            truncate content, inner
          end
        end
      end
    end
  end
end
