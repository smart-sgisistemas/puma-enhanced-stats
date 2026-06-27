# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module CLI
        # Static help text for modal tabs.
        module HelpContent
          TABS = [
            "Atalhos",
            "Seções",
            "SUMMARY",
            "Worker",
            "TOP & host",
            "Badges"
          ].freeze

          CONTENT = {
            "Atalhos" => [
              "d design  l layout  i request display  o sort  f filter",
              "O outsiders  t top+proc  W save  ?/h help  x clear filters",
              "j/k request line  [/] page  J/K workers  0-9 focus  Ctrl+C quit"
            ],
            "Seções" => %w[HEADER TOP PROCESSES SUMMARY WORKERS OUTSIDE\ PUMA FOOTER],
            "SUMMARY" => [
              "7 lines: workers, in-flight, dropped, truncated, backlog, busy, pool",
              "Optional Host vs Puma LabelLine when attribution warn/crit"
            ],
            "Worker" => [
              "synced_at LabelLine then puma MetricLines then rss/cpu from ps",
              "registry line and IN-FLIGHT table with scroll offsets"
            ],
            "TOP & host" => [
              "Load free text; CPU/Memory MetricLine grid with Puma ~ suffix",
              "Outsiders lazy top 3; degraded when CLI remote from Puma"
            ],
            "Badges" => [
              "ok green  info cyan  WARN yellow  CRIT red",
              "backlog > 0 always CRIT; requests_truncated always info"
            ]
          }.freeze

          module_function

          def tab_names = TABS
          def lines_for(tab) = CONTENT.fetch(tab, [])
        end
      end
    end
  end
end
