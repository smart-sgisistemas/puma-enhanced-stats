# frozen_string_literal: true

require "json"

module Puma
  module Enhanced
    module Stats
      module Status
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
