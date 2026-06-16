# frozen_string_literal: true

require_relative "field"

module Puma
  module Enhanced
    module Stats
      # Limits and field extractors for enhanced stats.
      #
      # Built by {DSL#enhanced_stats} in +puma.rb+, stored in
      # +launcher.config.options[:enhanced_stats]+, and assigned to
      # {CurrentRequests#config=} by {Launcher}.
      # Omit the block to use {Configuration.default}.
      #
      # Registered fields live in {#fields}, keyed by +:request+ and +:session+.
      #
      # @see DSL
      # @see Configuration.default
      # @see CurrentRequests#config
      class Configuration
        # @return [Array<Symbol>] allowed {#limit_policy} values
        LIMIT_POLICIES = %i[keep_longest reject_new].freeze

        # @!attribute [rw] request_limit
        #   Maximum in-flight requests tracked per worker.
        # @!attribute [rw] limit_policy
        #   Policy applied when the in-flight registry is full.
        # @!attribute [rw] sync_interval
        #   Worker ping interval in seconds. In cluster mode, overrides Puma's
        #   +worker_check_interval+. Also reported in snapshot +meta+.
        # @!attribute [rw] max_field_length
        #   Maximum byte length for extracted string values.
        # @!attribute [r] fields
        #   {Field} maps keyed by namespace (+:request+, +:session+), then field name.
        #   @return [Hash{Symbol => Hash{String => Field}}]
        attr_reader :request_limit, :limit_policy, :sync_interval, :max_field_length, :fields

        class << self
          # @return [Configuration] shared defaults when +enhanced_stats+ is omitted
          def default = @default ||= new
        end

        # Initializes default limits and built-in request fields (+method+,
        # +remote_ip+, +path_info+).
        #
        # @return [void]
        def initialize
          @fields = {
            request: {
              "method" => Field.new(name: "method", block: ->(env) { env["REQUEST_METHOD"] }),
              "remote_ip" => Field.new(name: "remote_ip", block: ->(env) { env["action_dispatch.remote_ip"] || env["REMOTE_ADDR"] }),
              "path_info" => Field.new(name: "path_info", block: ->(env) { (env["SCRIPT_NAME"] || "") + env["PATH_INFO"] })
            },
            session: {}
          }
          self.request_limit = 100
          self.limit_policy = :keep_longest
          self.sync_interval = 5
          self.max_field_length = 256
        end

        # Sets {#request_limit} after validating the value is a positive integer.
        #
        # @param value [Integer, String, #to_int]
        # @return [Integer]
        # @raise [Error] when +value+ is not a positive integer
        def request_limit= value
          request_limit = Integer value
          raise Error, "request_limit must be > 0" unless request_limit.positive?

          @request_limit = request_limit
        end

        # Sets {#limit_policy} after validating against {LIMIT_POLICIES}.
        #
        # @param value [Symbol, String]
        # @return [Symbol]
        # @raise [Error] when +value+ is not an allowed policy
        def limit_policy= value
          policy = value.to_sym
          raise Error, "invalid limit_policy #{value} (allowed: #{LIMIT_POLICIES.join(', ')})" unless LIMIT_POLICIES.include? policy

          @limit_policy = policy
        end

        # Sets {#sync_interval} after validating the value is a positive integer.
        #
        # @param value [Integer, String, #to_int]
        # @return [Integer]
        # @raise [Error] when +value+ is not a positive integer
        def sync_interval= value
          sync_interval = Integer value
          raise Error, "sync_interval must be > 0" unless sync_interval.positive?

          @sync_interval = sync_interval
        end

        # Sets {#max_field_length} after validating the value is a positive integer.
        #
        # @param value [Integer, String, #to_int]
        # @return [Integer]
        # @raise [Error] when +value+ is not a positive integer
        def max_field_length= value
          max_field_length = Integer value
          raise Error, "max_field_length must be > 0" unless max_field_length.positive?

          @max_field_length = max_field_length
        end

        # Returns registered fields for a namespace in insertion order.
        #
        # @param namespace [Symbol] +:request+ or +:session+
        # @return [Array<Field>]
        # @raise [KeyError] when +namespace+ is unknown
        def fields_for(namespace) = @fields.fetch(namespace).values

        # Registers or replaces {Field} instances for a namespace at request entry.
        #
        # +:request+ fields read from Rack +env+ (top-level keys on the entry).
        # +:session+ fields read from +env["rack.session"]+ (nested under +session+).
        #
        # Without a block, {Field#extract} reads +source+ via +[]+. With a block,
        # accepts exactly one name.
        #
        # @param namespace [Symbol, String] +:request+ or +:session+
        # @param names [Array<Symbol, String>]
        # @yield optional; block form accepts exactly one name
        # @yieldparam source [Hash] Rack +env+ or +rack.session+ hash
        # @return [void]
        # @raise [Error] when a block is given with more than one name
        def register_fields namespace, *names, &block
          namespace = namespace.to_sym
          raise Error, "#{namespace} with block accepts exactly one name" unless names.size == 1 if block

          names.each do |name|
            @fields[namespace][name.to_s] = Field.new(name: name, block: block)
          end
        end
      end
    end
  end
end
