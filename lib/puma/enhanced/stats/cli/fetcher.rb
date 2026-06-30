# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Puma
  module Enhanced
    module Stats
      module CLI
        # Fetches enhanced-stats JSON from the Puma control app.
        #
        # Resolves connection settings via {ControlDiscovery} on initialize unless
        # a resolved {ControlDiscovery::Entry} is supplied. Raises {Error} when the
        # URL is missing, auth fails, or the response is not valid JSON.
        class Fetcher
          class Error < StandardError; end

          # @param resolved [ControlDiscovery::Entry, nil]
          def initialize(resolved: nil, overrides: {})
            @resolved = resolved || ControlDiscovery.resolve(overrides: overrides)
          end

          # @return [Hash] parsed enhanced-stats payload
          def fetch
            uri = build_uri
            response = Net::HTTP.get_response uri
            handle_response response
          end

          # @return [Integer, nil] cluster master PID from the state file, if known
          def master_pid = @resolved.master_pid

          # @return [Integer, nil] worker_check_interval from Puma config, if known
          def worker_check_interval = @resolved.worker_check_interval

          private

          def build_uri
            base = http_base
            token = @resolved.token
            path = base.path.end_with?("/") ? "#{base.path}enhanced-stats" : "#{base.path}/enhanced-stats"
            query = token && !token.empty? ? "?token=#{URI.encode_www_form_component(token)}" : ""
            URI "#{base.scheme}://#{base.host}:#{base.port}#{path}#{query}"
          end

          def http_base
            raw = @resolved.control_url
            raise Error, "control URL required: configure activate_control_app in config/puma.rb" if raw.to_s.empty?

            normalize_control_url raw
          end

          def normalize_control_url(raw)
            uri = URI.parse raw
            case uri.scheme
            when "http", "https"
              uri
            when "tcp", "ssl"
              URI "http://#{uri.host}:#{uri.port}"
            else
              raise Error, "unsupported control URL scheme: #{uri.scheme} (use http or tcp)"
            end
          rescue URI::InvalidURIError => e
            raise Error, "invalid control URL: #{e.message}"
          end

          def handle_response(response)
            case response
            when Net::HTTPSuccess
              JSON.parse response.body
            when Net::HTTPForbidden
              raise Error, "authentication failed (403): check control app auth token in config/puma.rb"
            else
              raise Error, "enhanced-stats failed: HTTP #{response.code} #{response.body.to_s.strip}"
            end
          rescue JSON::ParserError => e
            raise Error, "invalid JSON response: #{e.message}"
          end
        end
      end
    end
  end
end
