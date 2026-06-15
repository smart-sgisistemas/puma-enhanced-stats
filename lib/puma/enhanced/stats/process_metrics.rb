# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      # Samples RSS and CPU for the current worker process via +ps+ on Linux/macOS.
      class ProcessMetrics
        # @return [Hash{String => nil}] process metrics when capture is unavailable
        EMPTY = { "rss_bytes" => nil, "cpu_percent" => nil }.freeze

        class << self
          # Samples RSS and CPU for the current process via +ps+.
          #
          # @return [Hash{String => Integer, Float, nil}] +rss_bytes+ and +cpu_percent+
          # @note Supported on Linux and macOS only; returns {EMPTY} elsewhere or on error
          def read
            return EMPTY unless RUBY_PLATFORM.match?(/linux|darwin/i)

            rss_kb, cpu = `ps -o rss=,%cpu= -p #{Process.pid} 2>/dev/null`.strip.split(/\s+/, 2)
            return EMPTY if rss_kb.nil? || rss_kb.empty?

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
