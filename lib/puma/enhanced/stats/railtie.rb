# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      # Rails integration for enhanced stats.
      #
      # Inserts {RequestStartMiddleware} as the outermost layer and appends
      # {RequestsMiddleware} as the innermost Rack layer (closest to the router).
      # Session middleware runs earlier on the request path, so +rack.session+
      # remains available for session field extractors.
      #
      # @see RequestStartMiddleware
      # @see RequestsMiddleware
      # @see Configuration#register_fields
      class Railtie < Rails::Railtie
        initializer "puma_enhanced_stats.middleware" do |app|
          app.middleware.insert_before 0, RequestStartMiddleware
          app.middleware.use RequestsMiddleware
        end
      end
    end
  end
end
