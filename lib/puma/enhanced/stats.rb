# frozen_string_literal: true

require_relative "stats/version"

require_relative "stats/field"
require_relative "stats/configuration"
require_relative "stats/current_requests"
require_relative "stats/body_proxy"
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
    # 1. Loads components ({RequestsMiddleware}, control {Status} patch, …)
    # 2. Prepends Puma classes and registers +enhanced-stats+ in {Puma::ControlCLI}
    # 3. Registers {Railtie} to insert {RequestStartMiddleware} and append
    #    {RequestsMiddleware} on the Rails middleware stack
    #
    # When the server starts, {Launcher} publishes +options[:enhanced_stats]+
    # (or {Configuration.default}) on {CurrentRequests#config=} before
    # {Puma::Launcher#run}.
    #
    # @see Configuration
    # @see DSL
    module Stats
      # Raised for invalid configuration values or field registration.
      #
      # @see Configuration
      class Error < StandardError; end

      Puma::DSL.prepend DSL
      Puma::Launcher.prepend Launcher
      Puma::App::Status.prepend Status
      Puma::Cluster::Worker.prepend ClusterWorker
      Puma::Cluster::WorkerHandle.prepend WorkerHandle
    end
  end

  # Registers the +enhanced-stats+ command for {Puma::ControlCLI} and
  # +pumactl enhanced-stats+.
  #
  # @see Puma::Enhanced::Stats::Status
  class ControlCLI
    old_verbose, $VERBOSE = $VERBOSE, nil
    # @return [Hash{String => String, nil}] control path map including +enhanced-stats+
    CMD_PATH_SIG_MAP = CMD_PATH_SIG_MAP.merge("enhanced-stats" => nil).freeze
    # @return [Array<String>] printable control commands including +enhanced-stats+
    PRINTABLE_COMMANDS = (PRINTABLE_COMMANDS + ["enhanced-stats"]).freeze
  ensure
    $VERBOSE = old_verbose
  end
end
