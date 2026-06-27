# frozen_string_literal: true

require_relative "cli/options"
require_relative "cli/user_config"
require_relative "cli/terminal"
require_relative "cli/keyboard"
require_relative "cli/colors"
require_relative "cli/format"
require_relative "cli/layout_grid"
require_relative "cli/alert_level"
require_relative "cli/bar"
require_relative "cli/box"
require_relative "cli/metric_line"
require_relative "cli/label_line"
require_relative "cli/layout_budget"
require_relative "cli/layout_registry"
require_relative "cli/scroll_state"
require_relative "cli/sync_freshness"
require_relative "cli/state_file"
require_relative "cli/control_discovery"
require_relative "cli/fetcher"
require_relative "cli/cgroup_memory"
require_relative "cli/host_metrics"
require_relative "cli/process_sampler"
require_relative "cli/resource_attribution"
require_relative "cli/request_field_catalog"
require_relative "cli/request_enricher"
require_relative "cli/request_filter"
require_relative "cli/request_sorter"
require_relative "cli/request_pipeline"
require_relative "cli/request_table"
require_relative "cli/severity_sorter"
require_relative "cli/header_renderer"
require_relative "cli/top_renderer"
require_relative "cli/summary_renderer"
require_relative "cli/worker_renderer"
require_relative "cli/outsiders_renderer"
require_relative "cli/footer_renderer"
require_relative "cli/frame_renderer"
require_relative "cli/help_content"
require_relative "cli/help_screen"
require_relative "cli/design_screen"
require_relative "cli/sort_screen"
require_relative "cli/filter_screen"
require_relative "cli/screen_manager"
require_relative "cli/stub_payload_builder"
require_relative "cli/stub_scenarios"
require_relative "cli/runner"

module Puma
  module Enhanced
    module Stats
      # Terminal dashboard for enhanced-stats JSON.
      #
      # Loaded by executables only — not when the gem boots Rails/Puma.
      #
      # @see docs/adr/0001-cli-load-isolated-from-rails.md
      module CLI
      end
    end
  end
end
