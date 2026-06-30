# frozen_string_literal: true

require_relative "stats/version"

require_relative "stats/field"
require_relative "stats/configuration"
require_relative "stats/middleware"

require "puma"
require "puma/dsl"
require "puma/launcher"
require "puma/app/status"
require "puma/cluster"
require "puma/control_cli"

require_relative "stats/snapshot"
require_relative "stats/cluster"
require_relative "stats/worker_handle"
require_relative "stats/worker"
require_relative "stats/single"
require_relative "stats/status"
require_relative "stats/launcher"
require_relative "stats/dsl"

require "rails/railtie"
require_relative "stats/railtie"

module Puma
  module Enhanced
    module Stats
      class Error < StandardError; end

      Puma::DSL.prepend DSL
      Puma::Launcher.prepend Launcher
      Puma::App::Status.prepend Status
      Puma::Cluster.prepend Cluster
      Puma::Cluster::WorkerHandle.prepend WorkerHandle
      Puma::Cluster::Worker.prepend Worker
      Puma::Single.prepend Single
    end
  end

  class ControlCLI
    old_verbose, $VERBOSE = $VERBOSE, nil
    CMD_PATH_SIG_MAP = CMD_PATH_SIG_MAP.merge("enhanced-stats" => nil).freeze
    PRINTABLE_COMMANDS = (PRINTABLE_COMMANDS + ["enhanced-stats"]).freeze
  ensure
    $VERBOSE = old_verbose
  end

  class << self
    def enhanced_stats_hash
      @get_stats.enhanced_stats
    end

    def enhanced_stats
      Puma::JSONSerialization.generate enhanced_stats_hash
    end
  end
end
