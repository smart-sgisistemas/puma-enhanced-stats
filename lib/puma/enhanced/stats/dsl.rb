# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module DSL
        class Builder
          def initialize(configuration) = @configuration = configuration

          def request_limit(value) = @configuration.request_limit = value

          def limit_policy(value) = @configuration.limit_policy = value

          def max_field_length(value) = @configuration.max_field_length = value

          def truncate_suffix(value) = @configuration.truncate_suffix = value

          def request(*names, &block) = @configuration.register_fields(:request, *names, &block)

          def session(*names, &block) = @configuration.register_fields(:session, *names, &block)
        end

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
