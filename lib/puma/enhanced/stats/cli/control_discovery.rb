# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module CLI
        # Resolves control-app connection settings from Puma configuration.
        #
        # Loads +config/puma.rb+  and environment-specific overrides via
        # {Puma::Configuration}. When a state file path is configured, values
        # from {StateFile} take precedence for URL, token, and master PID.
        # CLI flags  -S, -C, -T, -F override after config/state resolution.
        class ControlDiscovery
          # Resolved connection settings.
          Entry = Struct.new(:state_path, :control_url, :token, :master_pid, keyword_init: true)

          # @param env [Hash] environment variables  defaults to +ENV+
          # @param overrides [Hash{Symbol=>Object}] CLI connection overrides
          # @return [Entry]
          def self.resolve(env: ENV, overrides: {}) = new(env: env, overrides: overrides).resolve

          def initialize(env: ENV, overrides: {})
            @env = env
            @overrides = overrides
          end

          # @return [Entry]
          def resolve
            config_options = load_puma_configuration
            state_path = @overrides[:state_path] || config_options&.[](:state)
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

            control_url = @overrides[:control_url] if @overrides.key?(:control_url) && !@overrides[:control_url].to_s.empty?
            token = @overrides[:token] if @overrides.key?(:token)
            master_pid = StateFile.load(state_path)&.master_pid if state_path && master_pid.nil?

            Entry.new(state_path: state_path, control_url: control_url, token: token, master_pid: master_pid)
          end

          private

          def load_puma_configuration
            require "puma"
            require "puma/configuration"

            config = if @overrides[:config_path]
                       Puma::Configuration.new(config_files: [@overrides[:config_path]])
                     else
                       Puma::Configuration.new({}, {}, @env)
                     end
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
