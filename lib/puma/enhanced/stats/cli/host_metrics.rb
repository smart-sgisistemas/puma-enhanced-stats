# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module CLI
        # Reads host-level metrics from the local OS (Linux/macOS).
        #
        # Used by {TopRenderer} for the SYSTEM block. CPU percentages require
        # two samples; call {.reset_cpu_sample!} before the first {.read} in a
        # watch session so the first delta is meaningful.
        class HostMetrics
          Snapshot = Struct.new :load, :cpu, :memory, :swap, keyword_init: true
          CPU = Struct.new :usr, :sys, :idle, :usage, keyword_init: true
          Usage = Struct.new :used, :total, :ratio, keyword_init: true

          # Empty snapshot returned on unsupported platforms or error.
          EMPTY = Snapshot.new(
            load: nil,
            cpu: CPU.new(usr: nil, sys: nil, idle: nil, usage: nil),
            memory: Usage.new(used: nil, total: nil, ratio: nil),
            swap: Usage.new(used: nil, total: nil, ratio: nil)
          ).freeze

          @previous_cpu = nil

          class << self
            attr_accessor :previous_cpu

            # @return [Snapshot]
            def read
              return EMPTY unless RUBY_PLATFORM.match?(/linux|darwin/i)

              Snapshot.new(
                load: read_load,
                cpu: read_cpu,
                memory: read_memory,
                swap: read_swap
              )
            rescue StandardError
              EMPTY
            end

            # Clears the CPU baseline so the next {.read} starts a fresh delta.
            def reset_cpu_sample! = self.previous_cpu = nil

            private

            def read_load
              if linux?
                File.read("/proc/loadavg").split[0..2].map(&:to_f)
              else
                `sysctl -n vm.loadavg`.strip.split[1..3].map(&:to_f)
              end
            rescue StandardError
              nil
            end

            def read_cpu = linux? ? read_cpu_linux : read_cpu_darwin

            def read_cpu_linux
              line = File.readlines("/proc/stat").find { |row| row.start_with? "cpu " }
              return CPU.new unless line

              parts = line.split[1..].map(&:to_f)
              total = parts.sum
              idle = parts[3]
              sample = { total: total, idle: idle, usr: parts[0], sys: parts[1] }
              compute_cpu_delta sample
            end

            def read_cpu_darwin
              values = `sysctl -n kern.cp_time`.strip.split.map(&:to_f)
              total = values.sum
              idle = values[3]
              sample = { total: total, idle: idle, usr: values[0], sys: values[1] }
              compute_cpu_delta sample
            end

            def compute_cpu_delta sample
              previous = previous_cpu
              self.previous_cpu = sample
              return CPU.new(usr: 0, sys: 0, idle: 100, usage: 0.0) unless previous

              total_delta = sample[:total] - previous[:total]
              return CPU.new if total_delta <= 0

              idle_delta = sample[:idle] - previous[:idle]
              usr_delta = sample[:usr] - previous[:usr]
              sys_delta = sample[:sys] - previous[:sys]
              idle_pct = (idle_delta / total_delta * 100).round 1
              usr_pct = (usr_delta / total_delta * 100).round 1
              sys_pct = (sys_delta / total_delta * 100).round 1
              usage = (100.0 - idle_pct).round 1
              CPU.new usr: usr_pct, sys: sys_pct, idle: idle_pct, usage: usage / 100.0
            end

            def read_memory
              if linux?
                info = File.readlines("/proc/meminfo").each_with_object({}) do |line, hash|
                  key, value = line.split ":"
                  hash[key.strip] = value.to_i if value
                end
                total = info["MemTotal"].to_i * 1024
                available = info["MemAvailable"].to_i * 1024
                used = total - available
                ratio = total.positive? ? used.to_f / total : 0.0
                Usage.new used: used, total: total, ratio: ratio
              else
                page_size = `sysctl -n hw.pagesize`.strip.to_i
                memsize = `sysctl -n hw.memsize`.strip.to_i
                stats = `vm_stat`.lines.each_with_object({}) do |line, hash|
                  key, value = line.split ":"
                  hash[key.strip] = value.to_i if value
                end
                pages_used = stats.fetch("Pages active", 0) + stats.fetch("Pages wired down", 0)
                used = pages_used * page_size
                ratio = memsize.positive? ? used.to_f / memsize : 0.0
                Usage.new used: used, total: memsize, ratio: ratio
              end
            end

            def read_swap
              if linux?
                info = File.readlines("/proc/meminfo").each_with_object({}) do |line, hash|
                  key, value = line.split ":"
                  hash[key.strip] = value.to_i if value
                end
                total = info["SwapTotal"].to_i * 1024
                free = info["SwapFree"].to_i * 1024
                return Usage.new(used: 0, total: 0, ratio: 0.0) if total.zero?

                used = total - free
                Usage.new used: used, total: total, ratio: used.to_f / total
              else
                Usage.new used: 0, total: 0, ratio: 0.0
              end
            end

            def linux? = RUBY_PLATFORM.match?(/linux/i)
          end
        end
      end
    end
  end
end
