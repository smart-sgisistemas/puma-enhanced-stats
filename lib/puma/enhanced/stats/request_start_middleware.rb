# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      # Outermost Rails middleware that stamps request start time.
      #
      # Sets +HTTP_X_REQUEST_START+ to +t=<unix_float>+ when the header is
      # missing or blank. {CurrentRequests#started_at_for} reads this header
      # to populate +started_at+ on each entry. Compatible with nginx and
      # Heroku proxy formats when they set the header upstream.
      #
      # @example Header written by this middleware
      #   env["HTTP_X_REQUEST_START"] # => "t=1718381234.567"
      class RequestStartMiddleware
        # @param app [#call] downstream Rack application
        def initialize(app) = @app = app

        # Sets +HTTP_X_REQUEST_START+ when absent, then delegates to the app.
        #
        # @param env [Hash] Rack environment
        # @return [Array] Rack response triplet
        def call env
          env["HTTP_X_REQUEST_START"] = "t=#{Time.now.utc.to_f}" if env["HTTP_X_REQUEST_START"].to_s.strip.empty?

          @app.call env
        end
      end
    end
  end
end
