# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      # Named value extractor for a single request or session field.
      #
      # Instances are registered on {Configuration} via {#register_fields} or the
      # DSL. At request entry, {CurrentRequests} calls {#extract} with the Rack
      # +env+ (request fields) or +rack.session+ hash (session fields). String
      # truncation is applied later in {CurrentRequests#sanitize_field}, not here.
      #
      # @example Lookup by env key
      #   Field.new(name: "user_id") # reads source["user_id"]
      #
      # @example Custom extractor
      #   Field.new(name: "path") { |env| env["PATH_INFO"] }
      class Field
        # @!attribute [r] name
        #   Output key on the in-flight entry (+session+ hash for session fields).
        # @!attribute [r] block
        #   Optional proc; when absent, {#extract} reads +source+ via +[]+.
        attr_reader :name, :block

        # @param name [Symbol, String] field name written on the entry
        # @param block [Proc, nil] receives +env+ or session hash; omit for lookup
        def initialize name:, block: nil
          @name = name.to_s
          @block = block
        end

        # Reads a raw value from +source+ without truncation.
        #
        # With a {#block}, calls it with +source+. Without a block, reads
        # +source+ by {#name} (String or Symbol key).
        #
        # @param source [Hash] Rack +env+ or +rack.session+ hash
        # @return [Object, nil]
        def extract source
          if block
            block.call source
          else
            source[name] || source[name.to_s] || source[name.to_sym]
          end
        end
      end
    end
  end
end
