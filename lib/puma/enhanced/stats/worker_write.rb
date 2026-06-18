# frozen_string_literal: true

require "json"

module Puma
  module Enhanced
    module Stats
      # Prepends {Puma::Cluster::Worker#initialize} to wrap the worker pipe.
      #
      # Replaces +pipes[:worker_write]+ with a {WorkerWrite} decorator before
      # the worker process boots, so every PIPE_PING message to the master
      # carries a +enhanced_stats+ payload.
      module ClusterWorker
        # @param index [Integer]
        # @param master [IO]
        # @param launcher [Puma::Launcher]
        # @param pipes [Hash{Symbol => IO}]
        # @return [void]
        def initialize(index:, master:, launcher:, pipes:, **kwargs)
          pipes = pipes.merge(worker_write: WorkerWrite.new(pipes[:worker_write]))
          super(index: index, master: master, launcher: launcher, pipes: pipes, **kwargs)
        end
      end

      # IO decorator that augments worker ping messages with enhanced stats.
      #
      # Puma cluster workers periodically send PIPE_PING messages to the master.
      # This class intercepts those messages, merges +enhanced_stats+ from
      # {CurrentRequests.snapshot}, and forwards all other messages unchanged.
      # On parse failure or a missing +p{pid}+ prefix, the original message
      # is passed through.
      #
      # @example Ping payload after enhancement
      #   {
      #     backlog: 0,
      #     running: 2,
      #     enhanced_stats: {
      #       items: [...],
      #       dropped_count: 0,
      #       truncated: false,
      #       process: { rss_bytes: ..., cpu_percent: ... }
      #     }
      #   }
      class WorkerWrite
        # @param io [IO] underlying worker-to-master pipe
        # @return [WorkerWrite]
        def initialize(io) = @io = io

        # Writes +message+, enhancing worker pings with +enhanced_stats+.
        #
        # @param message [String]
        # @return [IO, Integer] return value of the underlying +IO#<<+
        def <<(message) = @io << (ping?(message) ? enhance_ping(message) : message)

        # Closes the underlying pipe.
        #
        # @return [void]
        def close = @io.close

        private

        # Returns +true+ when +message+ is a Puma worker ping (PIPE_PING prefix).
        def ping? message
          message.start_with? Puma::Const::PipeRequest::PIPE_PING
        end

        # Parses the ping JSON, merges +enhanced_stats+, and re-serializes.
        #
        # Replaces +PIPE_PING{pid}+ with +{+, parses the payload, and returns
        # +#{prefix}#{JSON.generate(body)}\n+. Returns the original +message+
        # when the prefix is missing or on any parse or build error.
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
