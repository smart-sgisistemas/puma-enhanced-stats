# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      # Version-specific Puma APIs shared by the gem and specs.
      module PumaCompat
        module_function

        # Worker ping prefix on the master/worker pipe (+p+ on all supported versions).
        #
        # @return [String]
        def pipe_ping_prefix
          if defined?(Puma::Const::PipeRequest::PIPE_PING)
            Puma::Const::PipeRequest::PIPE_PING
          else
            "p"
          end
        end

        # Builds {Puma::App::Status} with positional or keyword +token+ init.
        #
        # @param klass [Class]
        # @param launcher [Puma::Launcher]
        # @param token [String]
        # @return [Puma::App::Status]
        def status_app klass, launcher, token:
          if status_app_keyword_init?
            klass.new launcher, token: token
          else
            klass.new launcher, token
          end
        end

        # @return [Boolean]
        def status_app_keyword_init?
          @status_app_keyword_init ||= Puma::App::Status.instance_method(:initialize).parameters.any? do |type, name|
            name == :token && type == :key
          end
        end

        # Reads +before_worker_boot+ hooks registered on the configuration object.
        #
        # @param config [Puma::Configuration]
        # @return [Array]
        def before_worker_boot_hooks config
          options = config.respond_to?(:_options) ? config._options : config.options
          options.default_options[:before_worker_boot] || []
        end

        # @param hook_entry [Proc, Hash]
        # @return [Proc]
        def before_worker_boot_block hook_entry
          hook_entry.is_a?(Hash) ? hook_entry[:block] : hook_entry
        end

        # @param hook_entry [Proc, Hash]
        # @return [Boolean]
        def before_worker_boot_cluster_only? hook_entry
          hook_entry.is_a?(Hash) ? hook_entry[:cluster_only] == true : true
        end
      end
    end
  end
end
