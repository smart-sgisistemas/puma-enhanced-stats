# frozen_string_literal: true

require "json"
require "socket"

module Puma
  module Enhanced
    module Stats
      module CLI
        # Fake Puma control app serving GET /enhanced-stats (stdlib HTTP).
        class StubServer
          def initialize(host: "127.0.0.1", port: 9293, token: "dev", payload:)
            @host = host
            @port = port
            @bound_port = port
            @token = token
            @payload = payload
          end

          attr_reader :bound_port

          def start
            server = TCPServer.new @host, @port
            @bound_port = server.addr[1]
            loop do
              socket = server.accept
              Thread.new(socket) { |client| handle client }
            end
          rescue Interrupt, IOError, Errno::EBADF, Errno::ECONNABORTED
            nil
          ensure
            close_listener server
          end

          private

          def close_listener(server)
            return unless server
            return if server.closed?

            server.close
          rescue IOError, Errno::EBADF
            nil
          end

          def handle(socket)
            request_line = socket.gets
            return socket.close unless request_line

            _, path_query, = request_line.split
            path, query = path_query.split("?", 2)
            params = parse_query query
            headers = {}
            while (line = socket.gets) && line != "\r\n"
              key, value = line.split(": ", 2)
              headers[key.downcase] = value&.strip
            end

            body = if path != "/enhanced-stats"
                     not_found
                   elsif @token && !@token.empty? && params["token"] != @token
                     forbidden
                   else
                     ok JSON.generate(@payload)
                   end
            socket.write body
            socket.close
          rescue StandardError
            socket.close rescue nil
          end

          def parse_query(query)
            return {} unless query

            query.split("&").each_with_object({}) do |pair, hash|
              key, value = pair.split("=", 2)
              hash[key] = value
            end
          end

          def ok(json)
            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: #{json.bytesize}\r\nConnection: close\r\n\r\n#{json}"
          end

          def forbidden
            body = "Invalid auth token"
            "HTTP/1.1 403 Forbidden\r\nContent-Type: text/plain\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}"
          end

          def not_found
            body = "Not Found"
            "HTTP/1.1 404 Not Found\r\nContent-Type: text/plain\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}"
          end
        end
      end
    end
  end
end
