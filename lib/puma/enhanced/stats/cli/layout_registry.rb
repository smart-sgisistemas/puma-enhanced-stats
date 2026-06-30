# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module CLI
        # Resolves frame layout with minimum column requirements.
        class LayoutRegistry
          MODES = {
            "stacked" => 0,
            "compact" => 0,
            "focus" => 0,
            "split" => 100,
            "two_column" => 120,
            "grid" => 120
          }.freeze

          Result = Struct.new(:layout, :saved_layout, :hint, keyword_init: true)

          class << self
            def resolve(options, budget, mode: "cluster")
              requested = options.frame_layout.to_s
              if mode == "single" && %w[two_column grid split].include?(requested)
                return Result.new(
                  layout: "stacked",
                  saved_layout: requested,
                  hint: "layout: stacked (single mode has one server box)"
                )
              end

              min_cols = MODES.fetch(requested, 0)
              if budget.cols < min_cols
                return Result.new(
                  layout: "stacked",
                  saved_layout: requested,
                  hint: "layout: stacked  saved #{requested}, need #{min_cols} cols)"
                )
              end

              Result.new(layout: requested, saved_layout: requested, hint: nil)
            end
          end
        end
      end
    end
  end
end
