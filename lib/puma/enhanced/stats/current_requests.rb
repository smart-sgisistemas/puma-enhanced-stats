# frozen_string_literal: true

require "singleton"

module Puma
  module Enhanced
    module Stats
      class CurrentRequests
        include Singleton

        class << self
          private :instance

          def reset! = instance.reset!
          def register(env) = instance.register(env)
          def unregister(env) = instance.unregister(env)
          def config= value
            instance.config = value
          end

          def config = instance.config

          def snapshot = instance.snapshot
        end

        def initialize
          @mutex = Mutex.new
          @entries = {}
          @dropped_count = 0
          @truncated = false
          @config = Configuration.default
        end

        def config= value
          @mutex.synchronize { @config = value }
        end

        def config
          @mutex.synchronize { @config }
        end

        def reset!
          @mutex.synchronize do
            @entries.clear
            @dropped_count = 0
            @truncated = false
          end
        end

        def register env
          @mutex.synchronize do
            if full?
              @dropped_count += 1
              evict_newest! if @config.keep_longest?
              return if @config.reject_new?
            end
          end

          entry, truncated = build_entry env

          @mutex.synchronize do
            if full?
              @dropped_count += 1
              evict_newest! if @config.keep_longest?
              return if @config.reject_new?
            end

            @truncated = true if truncated
            @entries[env["action_dispatch.request_id"]] = entry
          end
        rescue StandardError
        end

        def unregister env
          @mutex.synchronize { @entries.delete env["action_dispatch.request_id"] }
        rescue StandardError
        end

        def snapshot
          @mutex.synchronize do
            {
              items: @entries.values,
              dropped_count: @dropped_count,
              truncated: @truncated
            }.tap do
              @dropped_count = 0
              @truncated = false
            end
          end
        end

        private

        def full?
          @entries.size >= @config.request_limit
        end

        def build_entry env
          request_fields, request_truncated = build_fields env, namespace: :request
          session_fields, session_truncated = build_fields env.fetch("rack.session", {}), namespace: :session
          [request_fields.merge(session: session_fields), request_truncated || session_truncated]
        end

        def build_fields source, namespace:
          values = {}
          truncated = false

          @config.fields_for(namespace).each do |field|
            value, field_truncated = sanitize_field field.extract(source)
            truncated ||= field_truncated
            values[field.name.to_sym] = value
          end

          [values, truncated]
        end

        def sanitize_field value
          return [nil, false] unless value

          string = value.to_s
          return [string, false] if string.length <= @config.max_field_length

          ["#{string[0, @config.max_field_length - @config.truncate_suffix.length]}#{@config.truncate_suffix}", true]
        end

        def evict_newest!
          return if @entries.empty?

          @entries.delete @entries.keys.last
        end
      end
    end
  end
end
