# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module CLI
        # Column budget for metric rows: label, value, flex gap, bar, badge.
        module LayoutGrid
          MIN_COLS = 80
          MAX_COLS = 100
          LABEL_WIDTH = 18
          TOP_LABEL_WIDTH = 8
          VALUE_WIDTH = 12
          HOST_VALUE_WIDTH = 18
          CPU_DETAIL_WIDTH = 19
          MIN_BAR_WIDTH = 10
          DEFAULT_BAR_WIDTH = 20
          BADGE_SLOT = 10
          BAR_BRACKETS = 2
          METRIC_TRAIL_GAP = 1

          module_function

          def cap_cols(cols) = [cols.to_i, MAX_COLS].min

          def content_width(box_cols) = [box_cols - 3, 10].max

          def too_narrow?(cols) = cols < MIN_COLS

          def narrow_error_message(cols)
            "Terminal too narrow: need at least #{MIN_COLS} columns (got #{cols}). " \
              "Resize the window or pass -w #{MIN_COLS}."
          end

          def bar_width_for(content_width, value_width: VALUE_WIDTH, label_width: LABEL_WIDTH)
            left_w = label_width + 1 + value_width
            reserved = left_w + METRIC_TRAIL_GAP + BAR_BRACKETS + METRIC_TRAIL_GAP + BADGE_SLOT
            bar_w = content_width - reserved
            [[bar_w, MIN_BAR_WIDTH].max, max_bar_width(content_width, value_width: value_width, label_width: label_width)].min
          end

          def max_bar_width(content_width, value_width: VALUE_WIDTH, label_width: LABEL_WIDTH)
            left_w = label_width + 1 + value_width
            reserved = left_w + METRIC_TRAIL_GAP + BAR_BRACKETS + METRIC_TRAIL_GAP + BADGE_SLOT
            [content_width - reserved, MIN_BAR_WIDTH].max
          end

          def metric_row(label:, value:, bar:, suffix:, colors:, content_width:, value_width: VALUE_WIDTH)
            metric_rows(
              label: label, value: value, bar: bar, suffix: suffix, colors: colors,
              content_width: content_width, value_width: value_width
            )
          end

          def metric_rows(label:, value:, bar:, suffix:, colors:, content_width:, value_width: VALUE_WIDTH,
                          label_width: LABEL_WIDTH)
            suffix_text = format_suffix(suffix, colors)
            trailing = metric_trailing(
              bar: bar, suffix_text: suffix_text, content_width: content_width,
              value_width: value_width, label_width: label_width
            )
            align_trailing_rows(
              metric_left_lines(label: label, value: value, value_width: value_width, label_width: label_width),
              trailing, content_width
            )
          end

          def label_row(label:, value:, badge:, colors:, content_width:)
            label_rows(label: label, value: value, badge: badge, colors: colors, content_width: content_width)
          end

          def label_rows(label:, value:, badge:, colors:, content_width:, label_width: LABEL_WIDTH)
            badge_text = format_badge(badge, colors)
            trailing = label_trailing(badge_text: badge_text, content_width: content_width, label_width: label_width)
            align_trailing_rows(
              metric_left_lines(label: label, value: value, label_width: label_width),
              trailing, content_width
            )
          end

          def cpu_breakdown_rows(label:, usr:, sys:, idle:, bar:, suffix:, content_width:,
                                 label_width: TOP_LABEL_WIDTH, value_width: HOST_VALUE_WIDTH)
            detail = format("user %4.1f%%  sys %4.1f%%  idle %4.1f%%", usr, sys, idle)
            [
              top_host_detail_row(label: label, detail: detail, label_width: label_width),
              top_host_usage_row(
                label: label, bar: bar, suffix: suffix, content_width: content_width,
                label_width: label_width, value_width: value_width
              )
            ]
          end

          def top_host_detail_row(label:, detail:, label_width: TOP_LABEL_WIDTH)
            "#{Format.pad_right(label.to_s, label_width)} #{detail}"
          end

          def top_host_usage_row(label:, bar:, suffix:, content_width:, label_width: TOP_LABEL_WIDTH,
                                 value_width: HOST_VALUE_WIDTH)
            trailing = metric_trailing(
              bar: bar, suffix_text: suffix.to_s, content_width: content_width,
              value_width: value_width, label_width: label_width
            )
            left = "#{Format.pad_right(label.to_s, label_width)} #{Format.pad_right('', value_width)}"
            flex = content_width - Format.display_length(left) - Format.display_length(trailing)
            flex = [flex, 0].max
            "#{left}#{' ' * flex}#{trailing}"
          end

          def top_cpu_row(label:, detail:, bar:, suffix:, content_width:)
            top_cpu_rows(label: label, detail: detail, bar: bar, suffix: suffix, content_width: content_width)
          end

          def top_cpu_rows(label:, detail:, bar:, suffix:, content_width:, label_width: TOP_LABEL_WIDTH)
            trailing = metric_trailing(
              bar: bar, suffix_text: suffix.to_s, content_width: content_width,
              value_width: CPU_DETAIL_WIDTH, label_width: label_width
            )
            label_part = Format.pad_right(label.to_s, label_width)
            detail_lines = fixed_slot_lines(detail.to_s, CPU_DETAIL_WIDTH)
            left_lines = detail_lines.map.with_index do |detail_line, index|
              if index.zero?
                "#{label_part} #{detail_line}"
              else
                "#{Format.pad_right('', label_width)} #{detail_line}"
              end
            end
            align_trailing_rows(left_lines, trailing, content_width)
          end

          def align_trailing_rows(left_lines, trailing, content_width)
            trail_len = Format.display_length(trailing)
            left_lines.map.with_index do |left, index|
              next left if index < left_lines.length - 1

              flex = content_width - Format.display_length(left) - trail_len
              flex = [flex, 0].max
              "#{left}#{' ' * flex}#{trailing}"
            end
          end

          def metric_left_lines(label:, value:, value_width: VALUE_WIDTH, label_width: LABEL_WIDTH)
            label_lines = fixed_slot_lines(label.to_s, label_width)
            value_lines = fixed_slot_lines(value.to_s, value_width)
            rows = []
            [label_lines.length, value_lines.length].max.times do |index|
              label_part = label_lines[index] || Format.pad_right("", label_width)
              value_part = value_lines[index] || Format.pad_right("", value_width)
              rows << "#{label_part} #{value_part}"
            end
            rows
          end

          def fixed_slot_lines(text, width)
            return [Format.pad_right("", width)] if text.empty?
            return [Format.pad_right(text, width)] if Format.display_length(text) <= width

            Format.wrap(text, width).map { |line| Format.pad_right(line, width) }
          end

          def metric_trailing(bar:, suffix_text:, content_width:, value_width: VALUE_WIDTH, label_width: LABEL_WIDTH)
            bar_w = bar_width_for(content_width, value_width: value_width, label_width: label_width)
            badge_cell = center_in_slot(suffix_text)
            "[#{pad_bar(bar, bar_w)}] #{badge_cell}"
          end

          def label_trailing(badge_text:, content_width:, label_width: LABEL_WIDTH, value_width: VALUE_WIDTH)
            bar_w = bar_width_for(content_width, value_width: value_width, label_width: label_width)
            bar_gap = " " * (bar_w + BAR_BRACKETS)
            badge_cell = center_in_slot(badge_text)
            "#{bar_gap} #{badge_cell}"
          end

          def pad_bar(bar, width)
            text = bar.to_s
            visible = Format.display_length(text)
            return Format.truncate_display(text, width) if visible > width

            "#{text}#{' ' * (width - visible)}"
          end

          def center_in_slot(text)
            Format.center_display(text, BADGE_SLOT)
          end

          def format_suffix(suffix, colors)
            return suffix if suffix.is_a?(String) && suffix.include?("\e")
            if suffix.is_a?(String) && !suffix.to_s.empty?
              begin
                sym = suffix.to_sym
                return suffix unless %i[ok warn crit info degraded].include?(sym)
              rescue StandardError
                return suffix
              end
            end

            level = suffix.is_a?(Symbol) ? suffix : :ok
            return "" if level == :ok && suffix.to_s.empty?

            colors ? colors.badge(level) : level.to_s.upcase
          end

          def format_badge(badge, colors)
            return "" if badge.nil? || badge == :ok

            level = badge.is_a?(Symbol) ? badge : :ok
            text = badge.is_a?(String) ? badge : level.to_s.upcase
            return text if text.include?("\e")

            colors ? colors.badge(level) : text
          end
        end
      end
    end
  end
end
