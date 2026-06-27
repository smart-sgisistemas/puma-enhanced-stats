# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module CLI
        # Resolves memory capacity for RSS ratios and TOP memory bars.
        #
        # Priority: cgroup v2 +memory.max+, cgroup v1 +memory.limit_in_bytes+  finite,
        # Linux +/proc/meminfo+ +MemTotal+, macOS +hw.memsize+.
        class CgroupMemory
          UNLIMITED = 2**62

          class << self
            # @return [Integer, nil]
            def total_bytes
              @total_bytes = resolve_total unless defined?(@total_bytes)
              @total_bytes
            end

            # @return [Boolean]
            def cgroup_limited?
              @cgroup_limited == true
            end

            # @return [String, nil] human hint for TOP footer, e.g. "512 MiB (cgroup)"
            def limit_hint
              return nil unless cgroup_limited? && total_bytes&.positive?

              "#{format_bytes(total_bytes)}  cgroup"
            end

            # Clears cached totals (tests).
            def reset!
              remove_instance_variable(:@total_bytes) if defined?(@total_bytes)
              remove_instance_variable(:@cgroup_limited) if defined?(@cgroup_limited)
            end

            # @return [Integer, nil] cgroup memory usage when limited
            def used_bytes
              total_bytes
              return nil unless cgroup_limited?

              read_cgroup_used
            end

            private

            def resolve_total
              @cgroup_limited = false
              if linux?
                total = read_cgroup_v2_max
                return nil if total == :unlimited

                total ||= read_cgroup_v1_limit
                if total&.positive?
                  @cgroup_limited = true
                  return total
                end
                return read_linux_memtotal
              end

              read_darwin_memsize if darwin?
            end

            def read_cgroup_v2_max
              path = "/sys/fs/cgroup/memory.max"
              return nil unless File.file?(path)

              value = File.read(path).strip
              return :unlimited if value.empty? || value == "max"

              value.to_i
            rescue StandardError
              nil
            end

            def read_cgroup_v1_limit
              path = "/sys/fs/cgroup/memory/memory.limit_in_bytes"
              return nil unless File.file?(path)

              value = File.read(path).strip.to_i
              return nil unless value.positive? && value < UNLIMITED

              value
            rescue StandardError
              nil
            end

            def read_cgroup_used
              v2 = "/sys/fs/cgroup/memory.current"
              return File.read(v2).strip.to_i if File.file?(v2)

              v1 = "/sys/fs/cgroup/memory/memory.usage_in_bytes"
              return File.read(v1).strip.to_i if File.file?(v1)

              nil
            rescue StandardError
              nil
            end

            def read_linux_memtotal
              line = File.readlines("/proc/meminfo").find { |row| row.start_with?("MemTotal:") }
              return nil unless line

              line.split[1].to_i * 1024
            rescue StandardError
              nil
            end

            def read_darwin_memsize
              `sysctl -n hw.memsize`.strip.to_i
            rescue StandardError
              nil
            end

            def format_bytes(size)
              if size >= 1_073_741_824
                format "%.1f GiB", size / 1_073_741_824.0
              elsif size >= 1_048_576
                format "%.0f MiB", size / 1_048_576.0
              elsif size >= 1024
                format "%.0f KiB", size / 1024.0
              else
                "#{size} B"
              end
            end

            def linux? = RUBY_PLATFORM.match?(/linux/i)
            def darwin? = RUBY_PLATFORM.match?(/darwin/i)
          end
        end
      end
    end
  end
end
