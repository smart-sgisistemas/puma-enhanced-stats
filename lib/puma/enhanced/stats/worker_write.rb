# frozen_string_literal: true

require "json"

module Puma
  module Enhanced
    module Stats
      # Prepends {WorkerWrite} on the worker-to-master pipe so ping messages
      # carry enhanced stats.
      #
      # @see WorkerWrite
      # @see WorkerHandle#ping!
      module ClusterWorker
        # Wraps +pipes[:worker_write]+ with {WorkerWrite} before boot.
        #
        # @param index [Integer] worker index
        # @param master [IO] master process pipe
        # @param launcher [Puma::Launcher] parent launcher
        # @param pipes [Hash{Symbol => IO}] cluster IPC pipes
        # @param kwargs [Hash] remaining arguments forwarded to Puma
        # @return [void]
        def initialize(index:, master:, launcher:, pipes:, **kwargs) = super(index: index, master: master, launcher: launcher, pipes: pipes.merge(worker_write: WorkerWrite.new(pipes[:worker_write])), **kwargs)
      end

      # IO decorator that injects +_enhanced_stats+ into worker ping JSON.
      #
      # Non-ping messages are passed through unchanged. When ping JSON cannot be
      # parsed, the original message is forwarded.
      #
      # @see ClusterWorker
      # @see WorkerHandle#ping!
      class WorkerWrite
        # @param io [IO] underlying worker-to-master pipe
        # @return [void]
        def initialize(io) = @io = io

        # Writes a message, enhancing worker pings with enhanced stats.
        #
        # @param message [String]
        # @return [void]
        def <<(message) = @io << ((ping? message) ? enhance_ping(message) : message)

        # Closes the underlying pipe.
        #
        # @return [void]
        def close = @io.close

        private

        def ping?(message) = message.start_with?(Puma::Const::PipeRequest::PIPE_PING)

        def enhance_ping message
          prefix = message[/\Ap\d+/]
          stats = message.delete_prefix(prefix).sub(/\s*\}\s*\n?\z/, "")
          body = JSON.parse("{#{stats}}").merge("_enhanced_stats" => enhanced_stats_payload)
          "#{prefix}#{JSON.generate(body)}\n"
        rescue StandardError
          message
        end

        def enhanced_stats_payload = CurrentRequestsRegistry.instance.snapshot.merge("process" => ProcessMetrics.read)
      end
    end
  end
end
