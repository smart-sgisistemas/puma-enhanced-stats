# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module CLI
        # Filter requests modal.
        class FilterScreen
          def render(options, budget)
            active = options.filters.empty? ? "—" : (options.filters.map { |k, v| "#{k}=#{v}" }.join(", "))
            lines = [
              "Active: #{active}",
              "Quick: G method=GET  P path=  U remote=  D dropped",
              "x clears filters in dashboard"
            ]
            Box.new(budget.cols).draw(title: "FILTER REQUESTS", lines: lines)
          end
        end
      end
    end
  end
end
