# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module CLI
        # Grid-aligned label row with badge right-aligned in the content area.
        class LabelLine
          LABEL_WIDTH = LayoutGrid::LABEL_WIDTH
          VALUE_WIDTH = LayoutGrid::VALUE_WIDTH
          BAR_SLOT = 23

          def initialize(label:, value:, badge: nil, colors: nil)
            @label = label
            @value = value
            @badge = badge
            @colors = colors
          end

          def render(content_width: LayoutGrid.content_width(LayoutGrid::MIN_COLS))
            LayoutGrid.label_rows(
              label: @label, value: @value, badge: @badge,
              colors: @colors, content_width: content_width
            )
          end
        end
      end
    end
  end
end
