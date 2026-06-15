# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module CLI
        # Reads a Puma state file for control URL, auth token, and master PID.
        #
        # Used when +puma-enhanced-stats -S tmp/puma.state+ is passed. Prefers
        # {Puma::StateFile} when available, with YAML fallback.
        #
        # @see Fetcher
        class StateFile
          # Parsed state file fields consumed by {Fetcher}.
          #
          # @!attribute [r] control_url
          #   @return [String, nil]
          # @!attribute [r] token
          #   @return [String, nil]
          # @!attribute [r] master_pid
          #   @return [Integer, nil]
          Entry = Struct.new :control_url, :token, :master_pid, keyword_init: true

          # @param path [String] path to the Puma state file
          # @return [Entry, nil]
          def self.load path
            new(path).load
          end

          # @param path [String]
          def initialize path
            @path = path
          end

          # @return [Entry, nil] +nil+ when the file is missing or unreadable
          def load
            return nil unless @path && File.file?(@path)

            if defined?(Puma::StateFile)
              return load_via_puma
            end

            load_via_yaml
          end

          private

          def load_via_puma
            state = Puma::StateFile.new @path
            control_url = state.control_url
            token = state.control_options&.dig(:auth_token) || state.control_options&.dig("auth_token")
            Entry.new control_url: control_url, token: token, master_pid: state.pid
          rescue StandardError
            load_via_yaml
          end

          def load_via_yaml
            require "yaml"
            data = YAML.safe_load File.read(@path), permitted_classes: [Symbol], aliases: true
            data ||= {}
            control_url = data["control_url"] || data[:control_url]
            token = data.dig("control_options", "auth_token") ||
                    data.dig(:control_options, :auth_token)
            master_pid = data["pid"] || data[:pid]
            Entry.new control_url: control_url, token: token, master_pid: master_pid
          rescue StandardError
            nil
          end
        end
      end
    end
  end
end
