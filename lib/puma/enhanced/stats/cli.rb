# frozen_string_literal: true

require_relative "cli/options"
require_relative "cli/terminal"
require_relative "cli/colors"
require_relative "cli/format"
require_relative "cli/bar"
require_relative "cli/box"
require_relative "cli/state_file"
require_relative "cli/fetcher"
require_relative "cli/layout_budget"
require_relative "cli/summary_aggregator"
require_relative "cli/request_table"
require_relative "cli/host_metrics"
require_relative "cli/top_renderer"
require_relative "cli/dashboard_renderer"
require_relative "cli/runner"

module Puma
  module Enhanced
    module Stats
      # Terminal dashboard for enhanced-stats JSON (v0.2.0+).
      #
      # Loaded by the +puma-enhanced-stats+ executable ({Runner}); not required when
      # the gem is loaded by Rails/Puma for server-side collection.
      #
      # @see Runner
      # @see DashboardRenderer
      module CLI
      end
    end
  end
end
