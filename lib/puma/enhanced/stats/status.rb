# frozen_string_literal: true

require "json"

module Puma
  module Enhanced
    module Stats
      # Adds +GET /enhanced-stats+ to the Puma control server.
      #
      # Prepended to {Puma::App::Status}. Reuses Puma's +authenticate+ and
      # +rack_response+ helpers. Returns JSON built by {Snapshot#build}.
      #
      # @example Control app request
      #   GET /enhanced-stats?token=secret
      #   # => 200 application/json
      module Status
        # Dispatches control commands; handles +enhanced-stats+ before Puma defaults.
        #
        # @param env [Hash] Rack environment
        # @return [Array] 403 without valid token; 200 with JSON body; otherwise super
        def call env
          if env["PATH_INFO"][/\/([^\/]+)$/, 1] == "enhanced-stats"
            return rack_response(403, "Invalid auth token", "text/plain") unless authenticate(env)

            return rack_response(200, JSON.generate(Snapshot.new(@launcher).build))
          end

          super
        end
      end
    end
  end
end
