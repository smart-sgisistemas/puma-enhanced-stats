# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      # Rack middleware that ensures +HTTP_X_REQUEST_START+ is present so
      # {CurrentRequests} can derive +started_at+ consistently (nginx/Heroku
      # +t=<unix>+ format).
      #
      # Inserted by {Railtie} as the outermost Rails middleware layer.
      #
      # @see CurrentRequests#register
      class RequestStartMiddleware
        # @param app [#call] downstream Rack app
        # @return [void]
        def initialize app
          @app = app
        end

        # Sets +HTTP_X_REQUEST_START+ when missing or blank, then delegates.
        #
        # @param env [Hash] Rack environment
        # @return [Array] Rack response triplet
        def call env
          if env["HTTP_X_REQUEST_START"].to_s.strip.empty?
            env["HTTP_X_REQUEST_START"] = "t=#{Time.now.utc.to_f}"
          end

          @app.call env
        end
      end
    end
  end
end
