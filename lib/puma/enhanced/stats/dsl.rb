# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      # Puma DSL for enhanced stats configuration in +puma.rb+.
      #
      # Prepended to {Puma::DSL} from {Stats} entrypoint. The +enhanced_stats+ block
      # builds a {Configuration} stored in +@options[:enhanced_stats]+; at
      # server start {Launcher} copies that reference to
      # {CurrentRequests#config=}.
      #
      # @example Custom limits and field extractors
      #   enhanced_stats do
      #     request_limit 100
      #     limit_policy :keep_longest
      #     sync_interval 5
      #     request :path { |env| env["PATH_INFO"] }
      #     session :user_id
      #   end
      #
      # Omit +enhanced_stats+ in +puma.rb+ to use {Configuration.default}.
      #
      # @see Configuration
      module DSL
        # Block evaluation context for {DSL#enhanced_stats}.
        #
        # Methods delegate to {Configuration}; see that class for defaults,
        # validation, and field extractor semantics.
        class Builder
          # @param configuration [Configuration] instance being built
          # @return [void]
          def initialize(configuration) = @configuration = configuration

          # Sets {#Configuration#request_limit}.
          #
          # @param value [Integer, String, #to_int]
          # @return [Integer]
          # @raise [Error] when +value+ is invalid
          def request_limit(value) = @configuration.request_limit = value

          # Sets {#Configuration#limit_policy}.
          #
          # @param value [Symbol, String]
          # @return [Symbol]
          # @raise [Error] when +value+ is invalid
          def limit_policy(value) = @configuration.limit_policy = value

          # Sets {#Configuration#sync_interval} (and Puma +worker_check_interval+ in cluster mode).
          #
          # @param value [Integer, String, #to_int]
          # @return [Integer]
          # @raise [Error] when +value+ is invalid
          def sync_interval(value) = @configuration.sync_interval = value

          # Sets {#Configuration#max_field_length}.
          #
          # @param value [Integer, String, #to_int]
          # @return [Integer]
          # @raise [Error] when +value+ is invalid
          def max_field_length(value) = @configuration.max_field_length = value

          # Registers request field extractors. See {Configuration#register_fields}.
          #
          # @param names [Array<Symbol, String>]
          # @yield [env] optional; block form accepts exactly one name
          # @yieldparam env [Hash] Rack environment
          # @return [void]
          # @raise [Error] when a block is given with more than one name
          def request(*names, &block) = @configuration.register_fields(:request, *names, &block)

          # Registers session field extractors. See {Configuration#register_fields}.
          #
          # @param names [Array<Symbol, String>]
          # @yield [rack_session] optional; block form accepts exactly one name
          # @yieldparam rack_session [Hash] +env["rack.session"]+
          # @return [void]
          # @raise [Error] when a block is given with more than one name
          def session(*names, &block) = @configuration.register_fields(:session, *names, &block)
        end

        # Builds enhanced stats configuration from a +puma.rb+ block.
        #
        # Evaluates the block in a {Builder} and stores the result in
        # +@options[:enhanced_stats]+.
        #
        # @yield evaluated in a {Builder}
        # @yieldreturn [void]
        # @raise [ArgumentError] when called without a block
        # @raise [Error] when a directive receives an invalid value
        # @return [Configuration]
        def enhanced_stats &block
          raise ArgumentError, "block required" unless block_given?

          configuration = Configuration.new
          Builder.new(configuration).instance_eval &block
          @options[:enhanced_stats] = configuration
        end
      end
    end
  end
end
