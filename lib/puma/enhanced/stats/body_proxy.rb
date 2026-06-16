# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      # Delegates to a Rack response body and runs a callback once when the body
      # finishes streaming ({RequestsMiddleware} uses this to unregister in-flight requests).
      #
      # @see RequestsMiddleware
      class BodyProxy
        # @param body [Object] Rack response body
        # @yield runs once after {#each} completes or {#close} is called
        # @return [void]
        def initialize body, &block
          @body = body
          @callback = block
          @called = false
        end

        # Streams the wrapped body and invokes the completion callback once.
        #
        # @yieldparam chunk [String]
        # @yield [chunk] optional block passed to the wrapped body
        # @return [Enumerator] when no block is given
        def each &block
          return enum_for :each unless block

          @body.each &block
          call_callback
        end

        # Closes the wrapped body and invokes the completion callback once.
        #
        # @return [void]
        def close
          @body.close if @body.respond_to? :close
          call_callback
        end

        # @param method [Symbol, String]
        # @param include_private [Boolean]
        # @return [Boolean]
        def respond_to_missing? method, include_private = false
          return true if @body.respond_to? method, include_private

          super
        end

        # Forwards unknown messages to the wrapped body.
        #
        # @param method [Symbol, String]
        # @param args [Array<Object>]
        # @return [Object]
        def method_missing method, *args, &block
          if method == :each
            return enum_for :each unless block

            @body.each do |chunk|
              yield chunk
            end
          else
            @body.public_send method, *args, &block
          end
        end

        private

        def call_callback
          return if @called

          @called = true
          @callback.call
        end
      end
    end
  end
end
