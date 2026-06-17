# frozen_string_literal: true

require "json"

module Puma
  module Enhanced
    module Stats
      # Prepends worker pipe setup to inject enhanced stats into cluster pings.
      #
      # Replaces +pipes[:worker_write]+ with a {WorkerWrite} decorator before
      # the worker process boots, so every PIPE_PING message to the master
      # carries a +_enhanced_stats+ payload.
      module ClusterWorker
        # Wraps the worker-to-master pipe with {WorkerWrite}.
        def initialize index:, master:, launcher:, pipes:, **kwargs
          super index: index, master: master, launcher: launcher, pipes: pipes.merge(worker_write: WorkerWrite.new(pipes[:worker_write])), **kwargs
        end
      end

      # IO decorator that augments worker ping messages with enhanced stats.
      #
      # Puma cluster workers periodically send PIPE_PING messages to the master.
      # This class intercepts those messages, merges +_enhanced_stats+ (from
      # {CurrentRequests.snapshot} and {ProcessMetrics.read}), and forwards
      # all other messages unchanged. On parse failure, the original message
      # is passed through.
      #
      # @example Ping payload after enhancement
      #   {
      #     "backlog" => 0,
      #     "running" => 2,
      #     "_enhanced_stats" => {
      #       "items" => [...],
      #       "dropped_count" => 0,
      #       "truncated" => false,
      #       "process" => { "rss_bytes" => ..., "cpu_percent" => ... }
      #     }
      #   }
      class WorkerWrite
        # @param io [IO] underlying worker-to-master pipe
        def initialize(io) = @io = io

        # Writes +message+, enhancing worker pings with +_enhanced_stats+.
        #
        # @param message [String]
        def <<(message) = @io << ((ping? message) ? enhance_ping(message) : message)

        # Closes the underlying pipe.
        def close = @io.close

        private

        # Returns +true+ when +message+ is a Puma worker ping (PIPE_PING prefix).
        def ping? message
          message.start_with? Puma::Const::PipeRequest::PIPE_PING
        end

        # Parses the ping JSON, merges +_enhanced_stats+, and re-serializes.
        #
        # Supports both brace-delimited and legacy Puma ping formats.
        # Returns the original +message+ on any parse or build error.
        def enhance_ping message
          json_start = message.index "{"
          if json_start
            prefix = message[0...json_start]
            body = JSON.parse message[json_start..].sub(/\s*\n\z/, "")
          else
            prefix = message[/\Ap\d+/] || ""
            stats = message.delete_prefix(prefix).sub(/\s*\}\s*\n?\z/, "")
            body = JSON.parse "{#{stats}}"
          end

          body = body.merge "_enhanced_stats" => enhanced_stats_payload
          "#{prefix}#{JSON.generate(body)}\n"
        rescue StandardError
          message
        end

        # Builds the +_enhanced_stats+ object attached to each ping.
        def enhanced_stats_payload = CurrentRequests.snapshot.merge("process" => ProcessMetrics.read)
      end
    end
  end
end
