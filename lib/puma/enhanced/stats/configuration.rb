# frozen_string_literal: true

require_relative "field"

module Puma
  module Enhanced
    module Stats
      class Configuration
        attr_reader :max_field_length

        class << self
          def default = @default ||= new
        end

        def initialize
          @fields = {
            request: {
              id: Field.new(name: "id", block: ->(env) { env["action_dispatch.request_id"] }),
              started_at: Field.new(name: "started_at", block: ->(env) { env["puma.enhanced_stats.started_at"] }),
              method: Field.new(name: "method", block: ->(env) { env["REQUEST_METHOD"] }),
              remote_ip: Field.new(name: "remote_ip", block: ->(env) { env["action_dispatch.remote_ip"] || env["REMOTE_ADDR"] }),
              path_info: Field.new(name: "path_info", block: ->(env) { (env["SCRIPT_NAME"] || "") + env["PATH_INFO"] })
            },
            session: {}
          }
          self.max_field_length = 256
        end

        def max_field_length= value
          max_field_length = Integer value
          raise Error, "max_field_length must be > 0" unless max_field_length.positive?

          @max_field_length = max_field_length
        end

        def fields_for(namespace) = @fields.fetch(namespace).values

        def register_fields namespace, *names, &block
          namespace = namespace.to_sym
          raise Error, "#{namespace} with block accepts exactly one name" unless names.size == 1 if block

          names.each do |name|
            @fields[namespace][name.to_sym] = Field.new name: name, block: block
          end
        end
      end
    end
  end
end
