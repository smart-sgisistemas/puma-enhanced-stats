# frozen_string_literal: true

require "singleton"

module Puma
  module Enhanced
    module Stats
      class ProcessMetrics
        include Singleton

        EMPTY = { rss_bytes: nil, cpu_percent: nil }.freeze

        class << self
          private :instance

          if RUBY_PLATFORM.match?(/linux/i)
            def snapshot = instance.snapshot
          else
            def snapshot = EMPTY
          end
        end

        def initialize
          @mutex = Mutex.new
          @last_cpu_sample = nil
        end

        def snapshot
          rss_bytes = read_rss_bytes
          return EMPTY if rss_bytes.nil?

          {
            rss_bytes: rss_bytes,
            cpu_percent: sample_cpu_percent
          }
        rescue StandardError
          EMPTY
        end

        private

        def sample_cpu_percent
          times = Process.times
          cpu_time_sec = times.utime + times.stime
          now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

          @mutex.synchronize do
            last = @last_cpu_sample
            @last_cpu_sample = { cpu_time_sec: cpu_time_sec, at: now }
            return nil unless last

            delta_cpu = cpu_time_sec - last[:cpu_time_sec]
            delta_wall = now - last[:at]
            return nil if delta_wall <= 0.0

            (100.0 * delta_cpu / delta_wall).round(2)
          end
        end

        def read_rss_bytes
          kb = File.read("/proc/self/status")[/^VmRSS:\s+(\d+)/, 1]
          kb&.to_i&.*(1024)
        end
      end
    end
  end
end
