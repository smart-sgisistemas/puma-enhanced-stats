# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module CLI
        # Resolves control-app connection settings from Puma configuration.
        #
        # Loads +config/puma.rb+ (and environment-specific overrides) via
        # {Puma::Configuration}. When a state file path is configured, values
        # from {StateFile} take precedence for URL, token, and master PID.
        class ControlDiscovery
          # Resolved connection settings from +puma.rb+ and optional state file.
          #
          # @!attribute state_path [String, nil]
          # @!attribute control_url [String, nil]
          # @!attribute token [String, nil]
          # @!attribute master_pid [Integer, nil]
          Entry = Struct.new :state_path, :control_url, :token, :master_pid, keyword_init: true

          # @param env [Hash] environment variables (defaults to +ENV+)
          # @return [Entry]
          def self.resolve(env: ENV) = new(env: env).resolve

          # @param env [Hash] environment variables (defaults to +ENV+)
          # @return [ControlDiscovery]
          def initialize(env: ENV) = @env = env

          # @return [Entry]
          def resolve
            config_options = load_puma_configuration
            state_path = config_options&.[](:state)
            control_url = config_options&.[](:control_url)
            token = config_options&.[](:control_auth_token)
            master_pid = nil

            if state_path
              entry = StateFile.load state_path
              if entry
                control_url = entry.control_url
                token = entry.token
                master_pid = entry.master_pid
              end
            end

            Entry.new state_path: state_path, control_url: control_url, token: token, master_pid: master_pid
          end

          private

          def load_puma_configuration
            require "puma"
            require "puma/configuration"

            config = Puma::Configuration.new({}, {}, @env)
            config.clamp
            config.options
          rescue StandardError, ScriptError
            nil
          end
        end
      end
    end
  end
end
