# frozen_string_literal: true

require_relative "field"

module Puma
  module Enhanced
    module Stats
      # Holds limits and field extractors for enhanced stats.
      #
      # Built by {DSL#enhanced_stats} in +puma.rb+ and stored in
      # +launcher.config.options[:enhanced_stats]+. {Launcher} copies the same
      # object to {CurrentRequests} at boot. Omit the DSL block to use
      # {Configuration.default}.
      #
      # Built-in request fields (+method+, +remote_ip+, +path_info+) are
      # registered in {#initialize}. Custom fields are added via
      # {#register_fields} or the DSL +request+ / +session+ directives.
      #
      # @example In puma.rb
      #   enhanced_stats do
      #     request_limit 50
      #     limit_policy :reject_new
      #     request :user_agent
      #     session :user_id
      #   end
      class Configuration
        # Allowed values for {Configuration#limit_policy=}.
        #
        # @return [Array<Symbol>]
        LIMIT_POLICIES = %i[keep_longest reject_new].freeze

        # @!attribute [rw] request_limit
        #   Maximum in-flight requests tracked per worker.
        # @!attribute [rw] limit_policy
        #   +:keep_longest+ evicts the newest entry when full; +:reject_new+ drops new ones.
        # @!attribute [rw] max_field_length
        #   Maximum character length for extracted string values.
        # @!attribute [r] fields
        #   @return [Hash{Symbol => Hash{String => Field}}] namespaces +:request+ and +:session+
        attr_reader :request_limit, :limit_policy, :max_field_length, :fields

        class << self
          # Shared defaults used when +enhanced_stats+ is omitted from +puma.rb+.
          #
          # @return [Configuration]
          def default = @default ||= new
        end

        # Registers built-in request fields and applies default limits.
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
          self.max_field_length = 256
        end

        # Sets the maximum number of in-flight entries per worker.
        #
        # @param value [Integer, String, #to_int]
        # @raise [Error] when +value+ is not a positive integer
        def request_limit= value
          request_limit = Integer value
          raise Error, "request_limit must be > 0" unless request_limit.positive?

          @request_limit = request_limit
        end

        # Sets the policy applied when the registry reaches {#request_limit}.
        #
        # @param value [Symbol, String] +:keep_longest+ or +:reject_new+
        # @raise [Error] when +value+ is not in {LIMIT_POLICIES}
        def limit_policy= value
          policy = value.to_sym
          raise Error, "invalid limit_policy #{value} (allowed: #{LIMIT_POLICIES.join(', ')})" unless LIMIT_POLICIES.include? policy

          @limit_policy = policy
        end

        # Sets the maximum character length for string field values.
        #
        # @param value [Integer, String, #to_int]
        # @raise [Error] when +value+ is not a positive integer
        def max_field_length= value
          max_field_length = Integer value
          raise Error, "max_field_length must be > 0" unless max_field_length.positive?

          @max_field_length = max_field_length
        end

        # Returns registered {Field} instances for a namespace in insertion order.
        #
        # @param namespace [Symbol] +:request+ or +:session+
        # @return [Array<Field>]
        # @raise [KeyError] when +namespace+ is unknown
        def fields_for(namespace) = @fields.fetch(namespace).values

        # Registers or replaces {Field} instances for a namespace.
        #
        # +:request+ fields are read from Rack +env+ and stored as top-level keys
        # on each entry. +:session+ fields are read from +env["rack.session"]+ and
        # stored under the +session+ key.
        #
        # Without a block, {Field#extract} looks up +source[name]+. With a block,
        # exactly one name must be given and the block receives the source hash.
        #
        # @param namespace [Symbol, String] +:request+ or +:session+
        # @param names [Array<Symbol, String>] one or more field names
        # @yield [source] optional extractor; block form accepts exactly one name
        # @yieldparam source [Hash] Rack +env+ or +rack.session+ hash
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
