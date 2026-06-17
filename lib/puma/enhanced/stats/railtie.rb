# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      # Rails integration for enhanced stats middleware.
      #
      # Inserts {RequestStartMiddleware} as the outermost layer so
      # +HTTP_X_REQUEST_START+ is set before any other middleware runs.
      # Appends {RequestsMiddleware} as the innermost layer (closest to the
      # router) so +rack.session+ is available for session field extractors.
      #
      # @example Middleware order (simplified)
      #   RequestStartMiddleware   # outermost
      #   ... session, cookies, etc.
      #   RequestsMiddleware       # innermost
      #   Rails router
      class Railtie < Rails::Railtie
        initializer "puma_enhanced_stats.middleware" do |app|
          app.middleware.insert_before 0, RequestStartMiddleware
          app.middleware.use RequestsMiddleware
        end
      end
    end
  end
end
