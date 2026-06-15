# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      # Rack middleware that registers in-flight requests in
      # {CurrentRequestsRegistry} at entry and unregisters when the response
      # body completes (or on hijack close).
      #
      # Inserted by {Railtie} after the Rails session store.
      #
      # @see CurrentRequestsRegistry
      class Middleware
        # @param app [#call] downstream Rack app
        # @param registry [CurrentRequestsRegistry]
        # @return [void]
        def initialize app, registry: CurrentRequestsRegistry.instance
          @app = app
          @registry = registry
        end

        # Registers the request, delegates to the app, and unregisters when the
        # response body completes. On hijack, unregisters when the hijacked IO
        # closes. When {CurrentRequestsRegistry#register} returns +nil+
        # (+:reject_new+ policy), passes through without tracking.
        #
        # @param env [Hash] Rack environment
        # @return [Array] Rack response triplet
        def call env
          id = @registry.register env
          return @app.call env unless id

          if env["rack.hijack?"]
            return hijack_call env, id
          end

          begin
            status, headers, body = @app.call env
            [status, headers, wrap_body(id, body, env)]
          rescue
            @registry.unregister id
            raise
          end
        end

        private

        def wrap_body id, body, env
          callback = -> { @registry.unregister id }

          if env["rack.after_reply"]
            env["rack.after_reply"] << callback
          end

          BodyProxy.new body, &callback
        end

        def hijack_call env, id
          status, headers, _body = @app.call env
          if (original = env["rack.hijack"])
            env["rack.hijack"] = proc do |io|
              begin
                original.call io
              ensure
                @registry.unregister id
              end
            end
          end
          [status, headers, []]
        end
      end
    end
  end
end
