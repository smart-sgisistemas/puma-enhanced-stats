# frozen_string_literal: true

require "json"

module Puma
  module Enhanced
    module Stats
      module ClusterWorker
        def initialize(index:, master:, launcher:, pipes:, **kwargs)
          pipes = pipes.merge(worker_write: WorkerWrite.new(pipes[:worker_write]))
          super(index: index, master: master, launcher: launcher, pipes: pipes, **kwargs)
        end
      end

      class WorkerWrite
        def initialize(io) = @io = io

        def <<(message) = @io << (ping?(message) ? enhance_ping(message) : message)

        def close = @io.close

        private

        def ping? message
          message.start_with? Puma::Const::PipeRequest::PIPE_PING
        end

        def enhance_ping message
          prefix = message[/\A#{Regexp.escape(Puma::Const::PipeRequest::PIPE_PING)}\d+/]
          return message unless prefix

          body = JSON.parse message.sub(prefix, "{").sub(/\s*\}\s*\n?\z/, "}"), symbolize_names: true
          body = body.merge enhanced_stats: CurrentRequests.snapshot
          "#{prefix}#{JSON.generate(body)}\n"
        rescue StandardError
          message
        end
      end
    end
  end
end
