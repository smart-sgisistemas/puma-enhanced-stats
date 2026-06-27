# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module CLI
        # Grid-aligned metric row with bar and badge right-aligned in the content area.
        class MetricLine
          LABEL_WIDTH = LayoutGrid::LABEL_WIDTH
          VALUE_WIDTH = LayoutGrid::VALUE_WIDTH
          BAR_SLOT = 23

          def initialize(label:, value:, suffix: :ok, colors: nil, bar_level: nil,
                         bar: nil, ratio: nil, bar_renderer: nil, backlog: false,
                         label_width: nil, value_width: nil)
            @label = label
            @value = value
            @suffix = suffix
            @bar_level = bar_level
            @colors = colors
            @bar = bar
            @ratio = ratio
            @bar_renderer = bar_renderer
            @backlog = backlog
            @label_width = label_width || LayoutGrid::LABEL_WIDTH
            @value_width = value_width || LayoutGrid::VALUE_WIDTH
          end

          def render(content_width: LayoutGrid.content_width(LayoutGrid::MIN_COLS))
            bar = resolve_bar(content_width)
            LayoutGrid.metric_rows(
              label: @label, value: @value, bar: bar, suffix: @suffix,
              colors: @colors, content_width: content_width,
              label_width: @label_width, value_width: @value_width
            )
          end

          private

          def resolve_bar(content_width)
            return @bar unless @bar_renderer && !@ratio.nil?

            suffix_text = LayoutGrid.format_suffix(@suffix, @colors)
            bar_w = LayoutGrid.bar_width_for(
              content_width, value_width: @value_width, label_width: @label_width
            )
            @bar_renderer.render(@ratio, width: bar_w, backlog: @backlog, level: @bar_level).first
          end
        end
      end
    end
  end
end
