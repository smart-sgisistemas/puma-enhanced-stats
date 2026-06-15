# frozen_string_literal: true

require "json"

module Puma
  module Enhanced
    module Stats
      # Adds +GET /enhanced-stats+ to the Puma control server.
      #
      # Prepended to {Puma::App::Status} from {Stats} entrypoint. Reuses Puma's
      # +authenticate+ and +rack_response+ helpers.
      #
      # @see Snapshot.build
      module Status
        # Handles +GET /enhanced-stats+ on the control server.
        #
        # Returns 403 when authentication fails; otherwise 200 with JSON from
        # {Snapshot.build}.
        #
        # @param env [Hash] Rack environment
        # @return [Array] Rack response triplet
        def call env
          if env["PATH_INFO"][/\/([^\/]+)$/, 1] == "enhanced-stats"
            return rack_response(403, "Invalid auth token", "text/plain") unless authenticate(env)

            return rack_response(200, JSON.generate(Snapshot.build(@launcher)))
          end

          super
        end
      end
    end
  end
end
