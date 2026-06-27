# frozen_string_literal: true

require "forwardable"

module Puma
  module Enhanced
    module Stats
      module CLI
        # Compares host/cgroup pressure with summed Puma PID usage ([ADR 0005]).
        class ResourceAttribution
          extend Forwardable
          Result = Struct.new(
            :puma_cpu, :puma_rss, :host_cpu, :host_mem,
            :cpu_gap, :mem_gap_ratio,
            :level, :summary_value, :cpu_suffix, :mem_suffix,
            :outsiders, :degraded,
            keyword_init: true
          )

          HOT_HOST_THRESHOLD = 0.60
          WARN_HOST_CPU = 75.0
          WARN_PUMA_CPU = 40.0
          WARN_CPU_GAP = 30.0
          CRIT_CPU_GAP = 80.0
          WARN_MEM_GAP = 0.15
          CRIT_MEM_GAP = 0.85
          CRIT_SWAP_RATIO = 0.50

          class << self
            # @param host [HostMetrics::Snapshot]
            # @param puma_pids [Array<Integer>]
            # @param process_by_pid [Hash{Integer=>ProcessSampler::Sample}]
            # @param degraded [Boolean] remote CLI — omit attribution UI
            # @return [Result]
            def compute(host:, puma_pids:, process_by_pid:, degraded: false)
              return new(degraded_result) if degraded

              puma_cpu = sum_cpu process_by_pid, puma_pids
              puma_rss = sum_rss process_by_pid, puma_pids
              host_cpu = host&.cpu&.usage.to_f * 100.0
              host_mem = host&.memory
              host_mem_ratio = host_mem&.ratio.to_f
              host_mem_total = host_mem&.total.to_i

              cpu_gap = [host_cpu - puma_cpu, 0.0].max
              mem_gap_ratio = if host_mem_total.positive?
                                host_mem_ratio - (puma_rss.to_f / host_mem_total)
                              else
                                0.0
                              end

              level = classify_level(
                host_cpu: host_cpu,
                puma_cpu: puma_cpu,
                cpu_gap: cpu_gap,
                mem_gap_ratio: mem_gap_ratio,
                host_mem_ratio: host_mem_ratio,
                swap_ratio: host&.swap&.ratio.to_f
              )

              new(
                Result.new(
                  puma_cpu: puma_cpu,
                  puma_rss: puma_rss,
                  host_cpu: host_cpu,
                  host_mem: host_mem,
                  cpu_gap: cpu_gap,
                  mem_gap_ratio: mem_gap_ratio,
                  level: level,
                  summary_value: summary_label(host_cpu, puma_rss, host_mem_total),
                  cpu_suffix: top_suffix(host, level, puma_cpu, :cpu),
                  mem_suffix: top_suffix(
                    host, level,
                    host_mem_total.positive? ? puma_rss.to_f / host_mem_total : 0.0,
                    :mem
                  ),
                  outsiders: [],
                  degraded: false
                )
              )
            end
          end

          def initialize(result)
            @result = result
            @outsiders_loaded = false
          end

          # @return [Result]
          attr_reader :result

          def_delegators :result, :level, :cpu_suffix, :mem_suffix, :summary_value, :degraded,
                         :puma_cpu, :puma_rss, :host_cpu, :cpu_gap, :mem_gap_ratio

          def degraded? = degraded

          # @return [Boolean]
          def warn_or_crit? = %i[warn crit].include?(level)

          # @return [Boolean]
          def show_summary_line? = warn_or_crit? && !summary_value.to_s.empty?

          # @return [Array<ProcessSampler::Outsider>]
          def outsiders = result.outsiders

          # Populates top outsiders via lazy +ps+ scan.
          #
          # @param exclude_pids [Array<Integer>]
          def load_outsiders!(exclude_pids:)
            return if degraded? || @outsiders_loaded

            result.outsiders.replace ProcessSampler.top_outsiders(exclude_pids: exclude_pids, limit: 3)
            @outsiders_loaded = true
          end

          private

          class << self
            def degraded_result
              Result.new(
                puma_cpu: nil, puma_rss: nil, host_cpu: nil, host_mem: nil,
                cpu_gap: nil, mem_gap_ratio: nil,
                level: :degraded, summary_value: nil, cpu_suffix: nil, mem_suffix: nil,
                outsiders: [], degraded: true
              )
            end

            def sum_cpu(process_by_pid, puma_pids)
              Array(puma_pids).sum do |pid|
                process_by_pid[pid]&.cpu_percent.to_f
              end
            end

            def sum_rss(process_by_pid, puma_pids)
              Array(puma_pids).sum do |pid|
                process_by_pid[pid]&.rss_bytes.to_i
              end
            end

            def classify_level(host_cpu:, puma_cpu:, cpu_gap:, mem_gap_ratio:, host_mem_ratio:, swap_ratio:)
              return :crit if swap_ratio > CRIT_SWAP_RATIO

              cpu_warn = host_cpu > WARN_HOST_CPU && puma_cpu < WARN_PUMA_CPU && cpu_gap >= WARN_CPU_GAP
              mem_warn = host_mem_ratio > HOT_HOST_THRESHOLD && mem_gap_ratio >= WARN_MEM_GAP
              return :ok unless cpu_warn || mem_warn

              cpu_crit = cpu_warn && cpu_gap >= CRIT_CPU_GAP
              mem_crit = mem_warn && mem_gap_ratio >= CRIT_MEM_GAP
              return :crit if cpu_crit || mem_crit

              :warn
            end

            def summary_label(host_cpu, puma_rss, host_mem_total)
              return nil unless host_mem_total.positive?

              puma_mem_pct = (puma_rss.to_f / host_mem_total * 100).round
              "CPU#{host_cpu.round}/M#{puma_mem_pct}"
            end

            def top_suffix(host, level, gap, kind)
              return nil if level == :ok

              host_hot = host_hot?(host)
              return nil unless host_hot
              return nil if gap.to_f <= 0

              case kind
              when :cpu
                "Puma ~#{gap.round}%"
              when :mem
                "Puma ~#{(gap * 100).round}%"
              end
            end

            def top_mem_suffix(host, level, gap, _host_mem_total)
              top_suffix(host, level, gap, :mem)
            end

            def host_hot?(host)
              host&.cpu&.usage.to_f >= HOT_HOST_THRESHOLD ||
                host&.memory&.ratio.to_f >= HOT_HOST_THRESHOLD
            end
          end
        end
      end
    end
  end
end
