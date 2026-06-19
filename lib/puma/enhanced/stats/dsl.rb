# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      # Puma DSL extension for configuring enhanced stats in +puma.rb+.
      #
      # Prepended to {Puma::DSL}. The +enhanced_stats+ block evaluates against a
      # {Builder} and stores the resulting {Configuration} in
      # +@options[:enhanced_stats]+. At server start, {Launcher} reads that option
      # and assigns it to {CurrentRequests}.
      #
      # @example Custom limits and field extractors
      #   # config/puma.rb
      #   enhanced_stats do
      #     request_limit 100
      #     limit_policy :keep_longest
      #     max_field_length 512
      #     request :path { |env| env["PATH_INFO"] }
      #     session :user_id
      #   end
      module DSL
        # Evaluation context for the +enhanced_stats+ block.
        #
        # Each method delegates to the underlying {Configuration} instance.
        class Builder
          # @param configuration [Configuration] instance being built
          def initialize(configuration) = @configuration = configuration

          # Sets {Configuration#request_limit}.
          #
          # @param value [Integer, String, #to_int]
          # @return [Integer]
          def request_limit(value) = @configuration.request_limit = value

          # Sets {Configuration#limit_policy}.
          #
          # @param value [Symbol, String]
          # @return [Symbol]
          def limit_policy(value) = @configuration.limit_policy = value

          # Sets {Configuration#max_field_length}.
          #
          # @param value [Integer, String, #to_int]
          # @return [Integer]
          def max_field_length(value) = @configuration.max_field_length = value

          # Sets {Configuration#truncate_suffix}.
          #
          # @param value [String, #to_s]
          # @return [String]
          def truncate_suffix(value) = @configuration.truncate_suffix = value

          # Registers request field extractors. See {Configuration#register_fields}.
          #
          # @param names [Array<Symbol, String>]
          # @yieldparam env [Hash] Rack environment when a block is given
          # @raise [Error] when a block is given with more than one name
          # @return [void]
          def request(*names, &block) = @configuration.register_fields(:request, *names, &block)

          # Registers session field extractors. See {Configuration#register_fields}.
          #
          # @param names [Array<Symbol, String>]
          # @yieldparam rack_session [Object] session object when a block is given
          # @raise [Error] when a block is given with more than one name
          # @return [void]
          def session(*names, &block) = @configuration.register_fields(:session, *names, &block)
        end

        # Builds a {Configuration} from a +puma.rb+ block.
        #
        # @yield evaluated in a {Builder}
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
