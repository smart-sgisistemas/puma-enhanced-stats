# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module CLI
        # Reads a Puma state file for runtime control-app settings.
        #
        # Prefers {Puma::StateFile} when available; falls back to YAML parsing.
        # Used by {ControlDiscovery} when +state+ is set in +puma.rb+.
        class StateFile
          # @!attribute control_url [String, nil]
          # @!attribute token [String, nil]
          # @!attribute master_pid [Integer, nil]
          Entry = Struct.new :control_url, :token, :master_pid, keyword_init: true

          # @param path [String] path to the state file
          # @return [Entry, nil]
          def self.load(path) = new(path).load

          # @param path [String]
          # @return [StateFile]
          def initialize(path) = @path = path

          # @return [Entry, nil]
          def load
            return nil unless @path && File.file?(@path)

            if defined?(Puma::StateFile)
              entry = load_via_puma
              return entry if entry&.control_url
            end

            load_via_yaml
          end

          private

          def load_via_puma
            require "puma/state_file"

            state = Puma::StateFile.new
            state.load @path
            Entry.new(
              control_url: state.control_url,
              token: state.control_auth_token,
              master_pid: state.pid
            )
          rescue StandardError
            nil
          end

          def load_via_yaml
            require "yaml"
            data = YAML.safe_load File.read(@path), permitted_classes: [Symbol], aliases: true
            data ||= {}
            control_url = data["control_url"] || data[:control_url]
            token = data["control_auth_token"] || data[:control_auth_token] ||
                    data.dig("control_options", "auth_token") ||
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
