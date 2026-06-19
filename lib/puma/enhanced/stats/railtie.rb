# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      # Rails integration for enhanced stats middleware.
      #
      # Appends {CurrentRequestsMiddleware} as the innermost layer (closest to the
      # router) so +rack.session+ is available for session field extractors.
      #
      # @example Middleware order (simplified)
      #   ... session, cookies, etc.
      #   CurrentRequestsMiddleware   # innermost
      #   Rails router
      class Railtie < Rails::Railtie
        initializer "puma_enhanced_stats.middleware" do |app|
          app.middleware.use CurrentRequestsMiddleware
        end
      end
    end
  end
end
