# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module CLI
        # Sort requests modal.
        class SortScreen
          FIELDS = %w[elapsed id method path_info remote_ip].freeze

          def render(options, budget)
            lines = FIELDS.map do |field|
              marker = options.sort_field == field ? "[*]" : "[ ]"
              dir = options.sort_field == field ? options.sort_dir : ""
              "#{marker} #{field} #{dir}"
            end
            Box.new(budget.cols).draw(title: "SORT REQUESTS", lines: lines)
          end
        end
      end
    end
  end
end
