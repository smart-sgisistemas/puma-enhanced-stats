# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module DSL
        class Builder
          def initialize configuration
            @configuration = configuration
          end

          def max_field_length(value) = @configuration.max_field_length = value

          def request(*names, &block)
            @configuration.register_fields :request, *names, &block
          end

          def session(*names, &block)
            @configuration.register_fields :session, *names, &block
          end
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
