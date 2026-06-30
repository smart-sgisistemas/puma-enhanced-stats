# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      class Middleware
        KEY = :"puma_enhanced_stats/current_env"
        STARTED_AT_KEY = "puma.enhanced_stats.started_at"

        def initialize(app) = @app = app

        def call env
          env[STARTED_AT_KEY] ||= Time.now.iso8601(6)
          Thread.current[KEY] = env
          @app.call env
        ensure
          Thread.current[KEY] = nil
        end
      end
    end
  end
end
