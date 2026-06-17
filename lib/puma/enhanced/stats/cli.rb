# frozen_string_literal: true

require_relative "cli/options"
require_relative "cli/terminal"
require_relative "cli/colors"
require_relative "cli/format"
require_relative "cli/bar"
require_relative "cli/box"
require_relative "cli/state_file"
require_relative "cli/control_discovery"
require_relative "cli/fetcher"
require_relative "cli/layout_budget"
require_relative "cli/summary_aggregator"
require_relative "cli/request_table"
require_relative "cli/worker_list"
require_relative "cli/host_metrics"
require_relative "cli/top_renderer"
require_relative "cli/dashboard_renderer"
require_relative "cli/request_only_renderer"
require_relative "cli/runner"

module Puma
  module Enhanced
    module Stats
      # Terminal dashboard for enhanced-stats JSON.
      #
      # Loaded by the +puma-enhanced-stats+ executable ({CLI::Runner}), not when
      # the gem is required by Rails/Puma for server-side collection.
      #
      # Connection settings are discovered from +config/puma.rb+ via
      # {ControlDiscovery} (same model as +pumactl+). In +--watch+ mode the
      # refresh interval follows +meta.worker_check_interval_seconds+ from the
      # server payload (Puma's +worker_check_interval+).
      #
      # @example One-shot dashboard
      #   puma-enhanced-stats
      #
      # @example Watch mode
      #   puma-enhanced-stats --watch
      module CLI
      end
    end
  end
end
