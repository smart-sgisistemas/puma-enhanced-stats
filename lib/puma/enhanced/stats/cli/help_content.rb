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
            "Seções" => %w[HEADER TOP PROCESSES SUMMARY WORKERS/SERVER OUTSIDE\ PUMA FOOTER],
            "SUMMARY" => [
              "Cluster: workers reporting, in-flight, backlog/busy/pool totals",
              "Single: in-flight, backlog, running, busy threads, pool capacity",
              "Optional Host vs Puma LabelLine when attribution warn/crit"
            ],
            "Worker" => [
              "Cluster: WORKER box with checkin + pool metrics + in-flight table",
              "Single: SERVER box with live pool metrics (no checkin) + in-flight table"
            ],
            "TOP & host" => [
              "Load free text; CPU/Memory MetricLine grid with Puma ~ suffix",
              "Outsiders lazy top 3; degraded when CLI remote from Puma"
            ],
            "Badges" => [
              "ok green  info cyan  WARN yellow  CRIT red",
              "backlog > 0 always CRIT"
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
