# frozen_string_literal: true

require "singleton"

require_relative "process_metrics"

module Puma
  module Enhanced
    module Stats
      # Thread-safe registry of in-flight HTTP requests for the current Puma worker.
      #
      # Each worker process holds its own singleton. {CurrentRequestsMiddleware} calls
      # {.register} when a request enters the Rails stack and {.unregister} when
      # the app returns. {Launcher} assigns a {Configuration} via {.config=} at
      # boot; forked cluster workers reuse that configuration object from the
      # parent process address space.
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

          # Class-level façade; each method delegates to the singleton instance.
          def reset! = instance.reset!
          def register(env) = instance.register(env)
          def unregister(env) = instance.unregister(env)
          def config=(value)
            instance.config = value
          end
          def snapshot = instance.snapshot
        end

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
        # insert. +truncated+ is set only when the entry is actually stored
        # (a full registry on the second check does not mark +@truncated+).
        # Swallows all errors so middleware never propagates failures.
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
        # * +truncated+ — whether any stored field was truncated since the last snapshot
        # * +process+ — RSS and CPU for the current worker ({ProcessMetrics.read})
        #
        # Resets +dropped_count+ and +truncated+ after reading so each worker ping
        # reports a delta for the sync interval.
        #
        # @return [Hash{Symbol => Object}]
        def snapshot
          @mutex.synchronize do
            {
              items: @entries.values,
              dropped_count: @dropped_count,
              truncated: @truncated,
              process: ProcessMetrics.read
            }.tap do
              @dropped_count = 0
              @truncated = false
            end
          end
        end

        private

        def full? = @entries.size >= @config.request_limit

        # @note Must be called while holding +@mutex+.
        def reject_new_when_full?
          return false unless full?
          return false unless @config.limit_policy == :reject_new

          @dropped_count += 1
          true
        end

        # @note Must be called while holding +@mutex+.
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
            started_at: Time.now.utc.iso8601(6)
          }.merge! request_fields

          session_fields, session_truncated = build_fields(env["rack.session"] || {}, namespace: :session)
          entry[:session] = session_fields unless session_fields.empty?

          [entry, request_truncated || session_truncated]
        end

        # Extracts and sanitizes configured fields for +namespace+ from +source+.
        #
        # +namespace+ selects which {Configuration#fields_for} list to use;
        # +source+ is already the Rack +env+ or +rack.session+ hash (see {#build_entry}).
        #
        # @param source [Hash]
        # @param namespace [Symbol] +:request+ or +:session+
        # @return [Array(Hash, Boolean)] field map and truncation flag
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

        # Converts +value+ to a string and truncates to {Configuration#max_field_length}.
        # Appends {Configuration#truncate_suffix} when non-empty, shortening the prefix
        # as needed; an empty suffix cuts at the limit with no marker.
        #
        # @return [Array(Object, Boolean)] sanitized value and whether truncation occurred
        def sanitize_field value
          return [nil, false] unless value

          string = value.to_s
          return [string, false] if string.length <= @config.max_field_length

          ["#{string[0, @config.max_field_length - @config.truncate_suffix.length]}#{@config.truncate_suffix}", true]
        end

        # Removes the most recently registered entry (last key in insertion order).
        #
        # @note Must be called while holding +@mutex+.
        def evict_newest!
          return if @entries.empty?

          @entries.delete @entries.keys.last
        end
      end
    end
  end
end
