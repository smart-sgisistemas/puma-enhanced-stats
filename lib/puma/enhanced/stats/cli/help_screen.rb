# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module CLI
        # Help modal (? / h).
        class HelpScreen
          def render(options, budget)
            tab = HelpContent.tab_names[options.help_tab % HelpContent.tab_names.size]
            lines = ["HELP ─ #{tab}", "←/→ or n/p tabs  Esc close", ""] + HelpContent.lines_for(tab)
            Box.new(budget.cols).draw(title: "HELP", lines: lines)
          end
        end
      end
    end
  end
end
