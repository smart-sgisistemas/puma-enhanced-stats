# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      class CurrentRequestsMiddleware
        def initialize(app) = @app = app

        def call env
          begin
            CurrentRequests.register env
            @app.call env
          ensure
            CurrentRequests.unregister env
          end
        end
      end
    end
  end
end
