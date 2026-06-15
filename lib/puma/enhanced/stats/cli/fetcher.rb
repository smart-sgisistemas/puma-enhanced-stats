# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Puma
  module Enhanced
    module Stats
      module CLI
        # Fetches enhanced-stats JSON from the Puma control app over HTTP.
        #
        # Resolves the control URL from {Options} and optional {StateFile} data,
        # then performs +GET /enhanced-stats+ with token query param when configured.
        #
        # @see Runner
        # @see StateFile
        class Fetcher
          # Raised when the control URL is invalid, auth fails, or the response is not JSON.
          class Error < StandardError; end

          # @param options [Options] parsed CLI flags
          def initialize options
            @options = options
            @state = options.state_path ? StateFile.load(options.state_path) : nil
          end

          # @return [Hash] parsed enhanced-stats JSON payload
          # @raise [Error] on connection, HTTP, or parse failures
          def fetch
            uri = build_uri
            response = Net::HTTP.get_response uri
            handle_response response
          end

          # Master PID from the state file (-S), used by {TopRenderer} for PROCESSES.
          #
          # @return [Integer, nil]
          def master_pid = @state&.master_pid

          private

          def build_uri
            base = http_base
            token = resolve_token
            path = base.path.end_with?("/") ? "#{base.path}enhanced-stats" : "#{base.path}/enhanced-stats"
            query = token && !token.empty? ? "?token=#{URI.encode_www_form_component(token)}" : ""
            URI "#{base.scheme}://#{base.host}:#{base.port}#{path}#{query}"
          end

          def resolve_token = @options.token || @state&.token

          def http_base
            raw = @options.url || @options.control_url || @state&.control_url
            raise Error, "control URL required: use -S, -C, or --url" if raw.nil? || raw.empty?

            normalize_control_url raw
          end

          def normalize_control_url raw
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

          def handle_response response
            case response
            when Net::HTTPSuccess
              JSON.parse response.body
            when Net::HTTPForbidden
              raise Error, "authentication failed (403): check --token / -T"
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
