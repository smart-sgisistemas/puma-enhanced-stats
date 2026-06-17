# frozen_string_literal: true

require_relative "stats/version"

require_relative "stats/field"
require_relative "stats/configuration"
require_relative "stats/current_requests"
require_relative "stats/request_start_middleware"
require_relative "stats/requests_middleware"
require_relative "stats/process_metrics"
require_relative "stats/snapshot"
require_relative "stats/status"
require_relative "stats/worker_handle"
require_relative "stats/worker_write"
require_relative "stats/launcher"
require_relative "stats/dsl"

require "puma"
require "puma/dsl"
require "puma/launcher"
require "puma/app/status"
require "puma/cluster"
require "puma/cluster/worker"
require "puma/cluster/worker_handle"
require "puma/control_cli"

require "rails/railtie"
require_relative "stats/railtie"

module Puma
  module Enhanced
    # Enhanced statistics plugin for Puma on Rails 7+.
    #
    # Require this file (via the gem entrypoint) to load the plugin. On require it:
    #
    # 1. Prepends {Stats::DSL}, {Stats::Launcher}, {Stats::Status},
    #    {Stats::ClusterWorker}, and {Stats::WorkerHandle} onto Puma classes
    # 2. Registers +enhanced-stats+ on {Puma::ControlCLI}
    # 3. Loads {Stats::Railtie}, which inserts middleware on the Rails stack
    #
    # At boot, {Stats::Launcher} assigns +options[:enhanced_stats]+ (or
    # {Stats::Configuration.default}) to {Stats::CurrentRequests}. In-flight
    # requests are tracked by {Stats::RequestsMiddleware}; snapshots are
    # exposed via +GET /enhanced-stats+ and +pumactl enhanced-stats+.
    #
    # @example Fetch JSON from a running server
    #   pumactl -S tmp/puma.state enhanced-stats
    #
    # @example Configure in puma.rb
    #   enhanced_stats do
    #     request_limit 100
    #     session :user_id
    #   end
    module Stats
      # Raised when a configuration value or field registration is invalid.
      class Error < StandardError; end

      Puma::DSL.prepend DSL
      Puma::Launcher.prepend Launcher
      Puma::App::Status.prepend Status
      Puma::Cluster::Worker.prepend ClusterWorker
      Puma::Cluster::WorkerHandle.prepend WorkerHandle
    end
  end

  # Extends {Puma::ControlCLI} with the +enhanced-stats+ command.
  #
  # Enables +pumactl enhanced-stats+ and routes the control app to
  # {Puma::Enhanced::Stats::Status}.
  class ControlCLI
    old_verbose, $VERBOSE = $VERBOSE, nil
    CMD_PATH_SIG_MAP = CMD_PATH_SIG_MAP.merge("enhanced-stats" => nil).freeze
    PRINTABLE_COMMANDS = (PRINTABLE_COMMANDS + ["enhanced-stats"]).freeze
  ensure
    $VERBOSE = old_verbose
  end
end
