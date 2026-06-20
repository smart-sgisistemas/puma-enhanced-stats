# frozen_string_literal: true

require_relative "stats/version"

require_relative "stats/field"
require_relative "stats/configuration"
require_relative "stats/current_requests"
require_relative "stats/current_requests_middleware"
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
    module Stats
      class Error < StandardError; end

      Puma::DSL.prepend DSL
      Puma::Launcher.prepend Launcher
      Puma::App::Status.prepend Status
      Puma::Cluster::Worker.prepend ClusterWorker
      Puma::Cluster::WorkerHandle.prepend WorkerHandle
    end
  end

  class ControlCLI
    old_verbose, $VERBOSE = $VERBOSE, nil
    CMD_PATH_SIG_MAP = CMD_PATH_SIG_MAP.merge("enhanced-stats" => nil).freeze
    PRINTABLE_COMMANDS = (PRINTABLE_COMMANDS + ["enhanced-stats"]).freeze
  ensure
    $VERBOSE = old_verbose
  end
end
