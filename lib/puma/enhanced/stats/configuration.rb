# frozen_string_literal: true

require_relative "field"

module Puma
  module Enhanced
    module Stats
      class Configuration
        LIMIT_POLICIES = %i[keep_longest reject_new].freeze

        DEFAULT_TRUNCATE_SUFFIX = "…"

        attr_reader :request_limit, :limit_policy, :max_field_length, :truncate_suffix, :fields

        class << self
          def default = @default ||= new
        end

        def initialize
          @fields = {
            request: {
              "id" => Field.new(name: "id", block: ->(env) { env["action_dispatch.request_id"] }),
              "started_at" => Field.new(name: "started_at", block: ->(_env) { Time.now.utc.iso8601(6) }),
              "method" => Field.new(name: "method", block: ->(env) { env["REQUEST_METHOD"] }),
              "remote_ip" => Field.new(name: "remote_ip", block: ->(env) { env["action_dispatch.remote_ip"] || env["REMOTE_ADDR"] }),
              "path_info" => Field.new(name: "path_info", block: ->(env) { (env["SCRIPT_NAME"] || "") + env["PATH_INFO"] })
            },
            session: {}
          }
          self.request_limit = 100
          self.limit_policy = :keep_longest
          self.max_field_length = 256
          self.truncate_suffix = DEFAULT_TRUNCATE_SUFFIX
        end

        def request_limit= value
          request_limit = Integer value
          raise Error, "request_limit must be > 0" unless request_limit.positive?

          @request_limit = request_limit
        end

        def limit_policy= value
          policy = value.to_sym
          raise Error, "invalid limit_policy #{value} (allowed: #{LIMIT_POLICIES.join(', ')})" unless LIMIT_POLICIES.include? policy

          @limit_policy = policy
        end

        def max_field_length= value
          max_field_length = Integer value
          raise Error, "max_field_length must be > 0" unless max_field_length.positive?

          @max_field_length = max_field_length
        end

        def truncate_suffix= value
          @truncate_suffix = value.to_s
        end

        def keep_longest? = @limit_policy == :keep_longest

        def reject_new? = @limit_policy == :reject_new

        def fields_for(namespace) = @fields.fetch(namespace).values

        def register_fields namespace, *names, &block
          namespace = namespace.to_sym
          raise Error, "#{namespace} with block accepts exactly one name" unless names.size == 1 if block

          names.each do |name|
            @fields[namespace][name.to_s] = Field.new name: name, block: block
          end
        end
      end
    end
  end
end
