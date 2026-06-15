# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      # Rails integration for enhanced stats.
      #
      # Inserts {Middleware} immediately after the session store so
      # +env["rack.session"]+ is populated before session fields are extracted
      # at request entry.
      #
      # @see Middleware
      # @see Configuration#register_fields
      class Railtie < Rails::Railtie
        # Inserts {Middleware} after the configured session store middleware.
        initializer "puma_enhanced_stats.middleware" do |app|
          session_klass = ActionDispatch::Session.resolve_store app.config.session_store
          app.middleware.insert_after session_klass, Middleware
        end
      end
    end
  end
end
