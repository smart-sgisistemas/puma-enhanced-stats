# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      # Innermost Rails middleware that tracks in-flight requests.
      #
      # Calls {CurrentRequests.register} before the app and
      # {CurrentRequests.unregister} in an +ensure+ block so entries are removed
      # when the Rails stack returns. Tracks time spent inside the app, not
      # response body streaming after +@app.call+ returns.
      #
      # Registry errors are swallowed by {CurrentRequests} and never affect the
      # HTTP response.
      #
      # @example Lifecycle per request
      #   CurrentRequests.register env   # on entry
      #   @app.call env                  # Rails handles the request
      #   CurrentRequests.unregister env # always, via ensure
      class CurrentRequestsMiddleware
        # @param app [#call] downstream Rack application
        def initialize(app) = @app = app

        # Registers the request, runs the app, and unregisters in +ensure+.
        #
        # @param env [Hash] Rack environment
        # @return [Array] Rack response triplet
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
