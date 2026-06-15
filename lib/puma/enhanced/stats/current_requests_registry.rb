# frozen_string_literal: true

require "securerandom"
require "singleton"

module Puma
  module Enhanced
    module Stats
      # Thread-safe store of in-flight requests for the current worker process.
      #
      # {Middleware} registers on entry; entries are built from {#config} fields
      # and removed when the response body finishes. Configuration is set by
      # {Launcher} from +options[:enhanced_stats]+ (or
      # {Configuration.default}) and inherited by forked workers.
      #
      # @see Middleware
      # @see Launcher
      # @see Configuration.default
      class CurrentRequestsRegistry
        include Singleton

        class << self
          # Clears the singleton registry (delegates to {#reset!}).
          #
          # @return [void]
          def reset! = instance.reset!
        end

        # @!attribute [rw] config
        #   Field extractors and limits applied when registering requests.
        #   @return [Configuration]
        attr_reader :config

        # Initializes an empty registry with {Configuration.default}.
        #
        # @return [void]
        def initialize
          @mutex = Mutex.new
          @entries = {}
          @dropped_count = 0
          @truncated = false
          @sequence = 0
          @config = Configuration.default
        end

        # Assigns field extractors and limits for new registrations.
        #
        # @param value [Configuration]
        # @return [Configuration]
        def config=(value)
          @mutex.synchronize { @config = value }
        end

        # Clears all entries and drop counters.
        #
        # @return [void]
        def reset!
          @mutex.synchronize do
            @entries.clear
            @dropped_count = 0
            @truncated = false
            @sequence = 0
          end
        end

        # Registers a request from Rack +env+.
        #
        # Entry +id+ prefers +env["action_dispatch.request_id"]+ (Rails), then
        # +env["HTTP_X_REQUEST_ID"]+, then a random hex fallback. A duplicate
        # +id+ replaces the previous entry and increments +dropped_count+.
        #
        # @param env [Hash] Rack environment
        # @return [String, nil] entry id, or +nil+ when {Configuration#limit_policy}
        #   is +:reject_new+ and the registry is full
        def register env
          id = started_at = sequence = configuration = nil

          @mutex.synchronize do
            configuration = @config
            return nil if reject_new_when_full? configuration

            evict_when_full_keep_longest! configuration

            id = request_id_for env
            if @entries.key? id
              @entries.delete id
              @dropped_count += 1
            end

            started_at = Time.now.utc
            @sequence += 1
            sequence = @sequence
          end

          entry, truncated = build_entry env, id: id, started_at: started_at, configuration: configuration

          @mutex.synchronize do
            return nil if reject_new_when_full? configuration

            evict_when_full_keep_longest! configuration

            @truncated = true if truncated
            @entries[id] = entry.merge "_seq" => sequence
          end

          id
        end

        # Removes an in-flight entry by id.
        #
        # @param id [String] entry id returned by {#register}
        # @return [void]
        def unregister(id) = @mutex.synchronize { @entries.delete id }

        # Returns a point-in-time view of in-flight requests for this worker.
        #
        # @return [Hash{String => Object}] +items+, +dropped_count+, +truncated+
        def snapshot
          @mutex.synchronize do
            items = @entries.values.sort_by { |entry| [entry["started_at"].to_s, entry["_seq"].to_i] }
              .map { |entry| entry.reject { |key| key == "_seq" } }
            {
              "items" => items,
              "dropped_count" => @dropped_count,
              "truncated" => @truncated
            }
          end
        end

        private

        def reject_new_when_full? configuration
          return false unless @entries.size >= configuration.request_limit
          return false unless configuration.limit_policy == :reject_new

          @dropped_count += 1
          true
        end

        def evict_when_full_keep_longest! configuration
          return unless @entries.size >= configuration.request_limit
          return unless configuration.limit_policy == :keep_longest

          evict_newest!
          @dropped_count += 1
        end

        def build_entry env, id:, started_at:, configuration:
          request_fields, request_truncated = build_fields env, namespace: :request, configuration: configuration
          entry = { "id" => id, "started_at" => started_at.utc.iso8601(6) }.merge! request_fields

          session_fields, session_truncated = build_fields env, namespace: :session, configuration: configuration
          entry["session"] = session_fields unless session_fields.empty?

          [entry, request_truncated || session_truncated]
        end

        def build_fields env, namespace:, configuration:
          rack_session = env["rack.session"] || {}
          source = namespace == :request ? env : rack_session
          values = {}
          truncated = false

          configuration.fields_for(namespace).each do |field|
            raw = field.extract source
            value, field_truncated = sanitize_field raw, configuration: configuration
            truncated ||= field_truncated
            values[field.name] = value
          end

          [values, truncated]
        end

        def sanitize_field value, configuration:
          return [nil, false] if value.nil?

          string = (value.is_a? String) ? value : value.to_s
          if string.bytesize > configuration.max_field_length
            [string.byteslice(0, configuration.max_field_length), true]
          else
            [string, false]
          end
        end

        def evict_newest!
          return if @entries.empty?

          newest_id, = @entries.max_by { |_, entry| [entry["started_at"].to_s, entry["_seq"].to_i] }
          @entries.delete newest_id
        end

        def request_id_for env
          id = env["action_dispatch.request_id"] || env["HTTP_X_REQUEST_ID"]
          id = id.to_s.strip
          return id unless id.empty?

          SecureRandom.hex 8
        end
      end
    end
  end
end
