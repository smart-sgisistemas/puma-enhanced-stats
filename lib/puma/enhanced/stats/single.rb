# frozen_string_literal: true

require_relative "snapshot"

module Puma
  module Enhanced
    module Stats
      module Single
        def enhanced_stats
          Snapshot.new(server: @server, worker_check_interval: 0).to_h
        end
      end
    end
  end
end
