# frozen_string_literal: true

require "singleton"

require_relative "process_metrics"

module Puma
  module Enhanced
    module Stats
      # Thread-safe registry of in-flight HTTP requests for the current Puma worker.
      #
      # Each worker process holds its own singleton. {RequestsMiddleware} calls
      # {.register} when a request enters the Rails stack and {.unregister} when
      # the app returns. {Launcher} assigns a {Configuration} via {.config=} at
      # boot; cluster workers inherit it after fork.
      #
      # Entries are keyed by +env["action_dispatch.request_id"]+. Field values
      # come from {Configuration#fields_for}. {.snapshot} is read by
      # {WorkerWrite} (cluster pings) and {Snapshot} (single mode); it returns
      # per-interval deltas for +dropped_count+ and +truncated+.
      #
      # The public API is entirely class methods; the instance is private.
      #
      # @example Register and read back
      #   CurrentRequests.register env
      #   CurrentRequests.snapshot # => { items: [...], dropped_count: 0, ... }
      #   CurrentRequests.unregister env
      class CurrentRequests
        include Singleton

        class << self
          private :instance

          # Clears all entries and counters. Delegates to {#reset!}.
          #
          # @return [void]
          def reset! = instance.reset!

          # Registers +env+ as in-flight. Delegates to {#register}.
          #
          # @param env [Hash] Rack environment
          # @return [void]
          def register(env) = instance.register(env)

          # Removes the entry for +env+. Delegates to {#unregister}.
          #
          # @param env [Hash] Rack environment
          # @return [void]
          def unregister(env) = instance.unregister(env)

          # Replaces the active {Configuration}. Delegates to {#config=}.
          #
          # @param value [Configuration]
          # @return [Configuration]
          def config=(value)
            instance.config = value
          end

          # Returns the current registry snapshot. Delegates to {#snapshot}.
          #
          # @return [Hash{Symbol => Object}] +:items+, +:dropped_count+, +:truncated+, +:process+
          def snapshot = instance.snapshot
        end

        # @!attribute [r] config
        #   @return [Configuration] active configuration

        # Builds an empty registry with default configuration.
        #
        # @return [void]
        def initialize
          @mutex = Mutex.new
          @entries = {}
          @dropped_count = 0
          @truncated = false
          @config = Configuration.default
        end

        # Replaces the active configuration under mutex.
        #
        # @param value [Configuration]
        # @return [Configuration]
        def config=(value)
          @mutex.synchronize { @config = value }
        end

        # Clears all in-flight entries and resets +dropped_count+ and +truncated+.
        #
        # Called from the cluster +before_worker_boot+ hook so a forked worker
        # starts with an empty registry.
        #
        # @return [void]
        def reset!
          @mutex.synchronize do
            @entries.clear
            @dropped_count = 0
            @truncated = false
          end
        end

        # Adds or updates an in-flight entry for +env+.
        #
        # Uses +env["action_dispatch.request_id"]+ as the hash key. A duplicate
        # id overwrites the previous entry. When the registry is full,
        # {#reject_new_when_full?} or {#evict_when_full_keep_longest!} applies
        # per {Configuration#limit_policy}.
        #
        # Field extraction runs outside the mutex; capacity is re-checked before
        # insert. Swallows all errors so middleware never propagates failures.
        #
        # @param env [Hash] Rack environment
        # @return [void]
        def register env
          @mutex.synchronize do
            return if reject_new_when_full?

            evict_when_full_keep_longest!
          end

          entry, truncated = build_entry env

          @mutex.synchronize do
            return if reject_new_when_full?

            evict_when_full_keep_longest!

            @truncated = true if truncated
            @entries[env["action_dispatch.request_id"]] = entry
          end
        rescue StandardError
        end

        # Removes the entry keyed by +env["action_dispatch.request_id"]+.
        #
        # Safe to call multiple times or when the id was never registered.
        # Swallows all errors so the middleware +ensure+ block never raises.
        #
        # @param env [Hash] Rack environment
        # @return [void]
        def unregister env
          @mutex.synchronize { @entries.delete env["action_dispatch.request_id"] }
        rescue StandardError
        end

        # Returns the current registry state and interval counters.
        #
        # The returned hash contains:
        #
        # * +items+ — array of in-flight entry hashes
        # * +dropped_count+ — registrations rejected or evicted since the last snapshot
        # * +truncated+ — whether any field value was truncated since the last snapshot
        # * +process+ — RSS and CPU for the current worker ({ProcessMetrics.read})
        #
        # Resets +dropped_count+ and +truncated+ after reading so each worker ping
        # reports a delta for the sync interval.
        #
        # @return [Hash{Symbol => Object}]
        def snapshot
          process = ProcessMetrics.read

          @mutex.synchronize do
            result = {
              items: @entries.values,
              dropped_count: @dropped_count,
              truncated: @truncated,
              process: process
            }
            @dropped_count = 0
            @truncated = false
            result
          end
        end

        private

        # Returns +true+ when the registry has reached {Configuration#request_limit}.
        def full? = @entries.size >= @config.request_limit

        # When policy is +:reject_new+ and the registry is full, increments
        # +dropped_count+ and returns +true+ so the caller skips registration.
        def reject_new_when_full?
          return false unless full?
          return false unless @config.limit_policy == :reject_new

          @dropped_count += 1
          true
        end

        # When policy is +:keep_longest+ and the registry is full, evicts the
        # newest entry and increments +dropped_count+ to make room.
        def evict_when_full_keep_longest!
          return unless full?
          return unless @config.limit_policy == :keep_longest

          evict_newest!
          @dropped_count += 1
        end

        # Builds one snapshot entry from +env+, merging configured request and
        # session fields.
        #
        # @return [Array(Hash, Boolean)] entry hash and whether any field was truncated
        def build_entry env
          request_fields, request_truncated = build_fields env, namespace: :request
          entry = {
            id: env["action_dispatch.request_id"],
            started_at: started_at_for(env).utc.iso8601(6)
          }.merge! request_fields

          session_fields, session_truncated = build_fields env, namespace: :session
          entry[:session] = session_fields unless session_fields.empty?

          [entry, request_truncated || session_truncated]
        end

        # Extracts and sanitizes all fields for +namespace+.
        #
        # @param namespace [Symbol] +:request+ reads +env+; +:session+ reads +rack.session+
        # @return [Array(Hash, Boolean)] field map and truncation flag
        def build_fields env, namespace:
          rack_session = env["rack.session"] || {}
          source = namespace == :request ? env : rack_session
          values = {}
          truncated = false

          @config.fields_for(namespace).each do |field|
            raw = field.extract source
            value, field_truncated = sanitize_field raw
            truncated ||= field_truncated
            values[field.name.to_sym] = value
          end

          [values, truncated]
        end

        # Converts +value+ to a string and truncates to {Configuration#max_field_length}.
        #
        # @return [Array(Object, Boolean)] sanitized value and whether truncation occurred
        def sanitize_field value
          return [nil, false] unless value

          string = value.is_a?(String) ? value : value.to_s
          if string.length > @config.max_field_length
            [string[0, @config.max_field_length], true]
          else
            [string, false]
          end
        end

        # Removes the most recently registered entry (last key in insertion order).
        def evict_newest!
          return if @entries.empty?

          @entries.delete @entries.keys.last
        end

        # Derives request start time from +HTTP_X_REQUEST_START+ or falls back to now.
        #
        # Accepts nginx/Heroku +t=<unix>+ formats: float seconds, integer seconds,
        # or millisecond timestamps (13+ digits).
        def started_at_for env
          header = env["HTTP_X_REQUEST_START"].to_s.strip
          return Time.now.utc if header.empty?

          value = header.sub(/\At=/, "")
          time = if value.match?(/\A\d{13,}\z/)
                   Time.at(value.to_i / 1000.0)
                 elsif value.match?(/\A\d+\.\d+\z/)
                   Time.at(value.to_f)
                 elsif value.match?(/\A\d+\z/)
                   Time.at(value.to_i)
                 end
          time&.utc || Time.now.utc
        rescue StandardError
          Time.now.utc
        end
      end
    end
  end
end
