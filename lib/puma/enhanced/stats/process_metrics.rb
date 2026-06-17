# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      # Samples RSS and CPU for the current worker process.
      #
      # Uses +ps+ on Linux and macOS. Returns {EMPTY} on unsupported platforms
      # or when the command fails. Included in worker snapshots via
      # {WorkerWrite#enhanced_stats_payload} and read directly in single mode
      # by {Snapshot}.
      #
      # @example
      #   ProcessMetrics.read
      #   # => { "rss_bytes" => 256_000_000, "cpu_percent" => 12.5 }
      class ProcessMetrics
        # Returned when process metrics cannot be sampled.
        EMPTY = { "rss_bytes" => nil, "cpu_percent" => nil }.freeze

        class << self
          # Samples RSS (bytes) and CPU percent for the current process.
          #
          # @return [Hash{String => Integer, Float, nil}]
          def read
            return EMPTY unless RUBY_PLATFORM.match?(/linux|darwin/i)

            rss_kb, cpu = `ps -o rss=,%cpu= -p #{Process.pid} 2>/dev/null`.strip.split(/\s+/, 2)
            return EMPTY if rss_kb.to_s.empty?

            {
              "rss_bytes" => rss_kb.to_i * 1024,
              "cpu_percent" => cpu.to_f.round(2)
            }
          rescue StandardError
            EMPTY
          end
        end
      end
    end
  end
end
