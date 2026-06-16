# frozen_string_literal: true

require "securerandom"
require "singleton"

module Puma
  module Enhanced
    module Stats
      # Thread-safe store of in-flight requests for the current worker process.
      #
      # {RequestsMiddleware} registers on entry; entries are built from {#config} fields
      # and removed when the response body finishes. Configuration is set by
      # {Launcher} from +options[:enhanced_stats]+ (or
      # {Configuration.default}) and inherited by forked workers.
      #
      # @see RequestsMiddleware
      # @see Launcher
      # @see Configuration.default
      class CurrentRequests
        include Singleton

        class << self
          # Clears the singleton (delegates to {#reset!}).
          #
          # @return [void]
          def reset! = instance.reset!
        end

        # @!attribute [rw] config
        #   Field extractors and limits applied when registering requests.
        #   @return [Configuration]
        attr_reader :config

        # @return [void]
        def initialize
          @mutex = Mutex.new
          @entries = {}
          @dropped_count = 0
          @truncated = false
          @config = Configuration.default
        end

        # @param value [Configuration]
        # @return [Configuration]
        def config=(value)
          @mutex.synchronize { @config = value }
        end

        # @return [void]
        def reset!
          @mutex.synchronize do
            @entries.clear
            @dropped_count = 0
            @truncated = false
          end
        end

        # Registers a request from Rack +env+.
        #
        # Entry +id+ prefers +env["action_dispatch.request_id"]+ (Rails), then
        # +env["HTTP_X_REQUEST_ID"]+, then a random hex fallback. A duplicate
        # +id+ replaces the previous entry and increments +dropped_count+.
        #
        # @param env [Hash] Rack environment
        # @return [String, nil] entry id, or +nil+ when {#config} {#limit_policy}
        #   is +:reject_new+ and the registry is full
        def register env
          id = started_at = nil

          @mutex.synchronize do
            return nil if reject_new_when_full?

            evict_when_full_keep_longest!

            id = request_id_for env
            drop_duplicate_id! id
            started_at = started_at_for env
          end

          entry, truncated = build_entry env, id: id, started_at: started_at

          @mutex.synchronize do
            return nil if reject_new_when_full?

            evict_when_full_keep_longest!

            @truncated = true if truncated
            @entries[id] = entry
          end

          id
        end

        # @param id [String] entry id returned by {#register}
        # @return [void]
        def unregister(id) = @mutex.synchronize { @entries.delete id }

        # Returns current in-flight items and meta counters since the previous
        # {#snapshot} (or process start). Resets +dropped_count+ and +truncated+
        # after reading so each observation reports a delta for the sync interval.
        #
        # @return [Hash{String => Object}] +items+, +dropped_count+, +truncated+
        def snapshot
          @mutex.synchronize do
            result = {
              "items" => @entries.values,
              "dropped_count" => @dropped_count,
              "truncated" => @truncated
            }
            @dropped_count = 0
            @truncated = false
            result
          end
        end

        private

        def reject_new_when_full?
          return false unless @entries.size >= @config.request_limit
          return false unless @config.limit_policy == :reject_new

          @dropped_count += 1
          true
        end

        def evict_when_full_keep_longest!
          return unless @entries.size >= @config.request_limit
          return unless @config.limit_policy == :keep_longest

          evict_newest!
          @dropped_count += 1
        end

        def drop_duplicate_id! id
          return unless @entries.key? id

          @entries.delete id
          @dropped_count += 1
        end

        def build_entry env, id:, started_at:
          request_fields, request_truncated = build_fields env, namespace: :request
          entry = { "id" => id, "started_at" => started_at.utc.iso8601(6) }.merge! request_fields

          session_fields, session_truncated = build_fields env, namespace: :session
          entry["session"] = session_fields unless session_fields.empty?

          [entry, request_truncated || session_truncated]
        end

        def build_fields env, namespace:
          rack_session = env["rack.session"] || {}
          source = namespace == :request ? env : rack_session
          values = {}
          truncated = false

          @config.fields_for(namespace).each do |field|
            raw = field.extract source
            value, field_truncated = sanitize_field raw
            truncated ||= field_truncated
            values[field.name] = value
          end

          [values, truncated]
        end

        def sanitize_field value
          return [nil, false] if value.nil?

          string = (value.is_a? String) ? value : value.to_s
          if string.bytesize > @config.max_field_length
            [string.byteslice(0, @config.max_field_length), true]
          else
            [string, false]
          end
        end

        def evict_newest!
          return if @entries.empty?

          @entries.delete @entries.keys.last
        end

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
