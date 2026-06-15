# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      # Named value extractor registered by {Configuration#register_fields}.
      #
      # Each field has an output {#name} and an optional {#block}. At request
      # entry, {CurrentRequestsRegistry} calls {#extract} with +env+ (request
      # fields) or +rack.session+ (session fields). String truncation happens
      # later in the registry, not here.
      #
      # Default request fields (+remote_ip+, +method+, +path_info+) are registered
      # in {Configuration#initialize}.
      #
      # @see Configuration#register_fields
      # @see CurrentRequestsRegistry
      class Field
        # @!attribute [r] name
        #   Key written on the in-flight entry (+session+ hash for session fields).
        #   @return [String]
        # @!attribute [r] block
        #   Optional extractor proc. When absent, {#extract} reads +source+ via +[]+.
        #   @return [Proc, nil]
        attr_reader :name, :block

        # @param name [Symbol, String]
        # @param block [Proc, nil] receives +env+ or the session hash; omit to use
        #   +source+ lookup
        # @return [void]
        def initialize name:, block: nil
          @name = name.to_s
          @block = block
        end

        # Extracts a raw value from +source+.
        #
        # With a {#block}, calls it with +source+. Without a block, reads
        # +source+ via +name+ (String or Symbol key).
        #
        # @param source [Hash] Rack +env+ or +rack.session+ hash
        # @return [Object, nil] unsanitized value; truncation is applied by
        #   {CurrentRequestsRegistry}
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
