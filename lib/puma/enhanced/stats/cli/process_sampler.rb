# frozen_string_literal: true

require_relative "cgroup_memory"

module Puma
  module Enhanced
    module Stats
      module CLI
        # Samples local process metrics via +ps+ for Puma worker/master PIDs.
        #
        # Returns +nil+ fields when a PID is not visible to the CLI (degraded /
        # remote mode). Does not mutate the JSON payload ([ADR 0002]).
        class ProcessSampler
          Sample = Struct.new(:pid, :cpu_percent, :mem_percent, :rss_bytes, keyword_init: true)
          Outsider = Struct.new(:pid, :cpu_percent, :mem_percent, :rss_bytes, :command, keyword_init: true)

          class Runner
            def ps_batch(list)
              `ps -o pid=,pcpu=,pmem=,rss= -p #{list} 2>/dev/null`
            end

            def ps_outsiders
              `ps -eo pid=,pcpu=,pmem=,rss=,comm= --sort=-pcpu 2>/dev/null`
            end
          end

          class << self
            # @param pid [Integer]
            # @return [Sample, nil]
            def sample(pid)
              sample_pids([pid])[pid]
            end

            # @param pids [Array<Integer>]
            # @return [Hash{Integer=>Sample}]
            def sample_pids(pids)
              list = Array(pids).compact.uniq
              return {} if list.empty?

              lookup = ps_batch_lookup list
              list.each_with_object({}) do |pid, hash|
                stats = lookup[pid]
                hash[pid] = stats || Sample.new(pid: pid, cpu_percent: nil, mem_percent: nil, rss_bytes: nil)
              end
            end

            # @param workers [Array<Hash>] JSON worker rows
            # @param master_pid [Integer, nil]
            # @return [Hash{Integer=>Sample}]
            def sample_all(workers, master_pid: nil)
              pids = Array(workers).map { |worker| worker["pid"] }.compact
              pids << master_pid if master_pid
              sample_pids pids
            end

            # @return [Integer, nil] denominator for RSS ratios
            def memory_capacity_bytes = CgroupMemory.total_bytes

            # Lazy scan for top non-Puma processes by CPU.
            #
            # @param exclude_pids [Array<Integer>]
            # @param limit [Integer]
            # @return [Array<Outsider>]
            def top_outsiders(exclude_pids:, limit: 3)
              excluded = Array(exclude_pids).compact.to_set
              output = run_ps_outsiders
              return [] if output.to_s.strip.empty?

              output.each_line.filter_map do |line|
                pid, cpu, mem, rss, command = line.strip.split /\s+/, 5
                next if pid.nil? || excluded.include?(pid.to_i)

                Outsider.new(
                  pid: pid.to_i,
                  cpu_percent: cpu.to_f,
                  mem_percent: mem.to_f,
                  rss_bytes: rss.to_i * 1024,
                  command: command.to_s
                )
              end.first(limit)
            rescue StandardError
              []
            end

            private

            def ps_batch_lookup(pids)
              list = pids.join(",")
              output = run_ps_batch list
              return {} if output.to_s.strip.empty?

              output.each_line.with_object({}) do |line, hash|
                pid, cpu, mem, rss = line.strip.split /\s+/, 4
                next unless pid

                hash[pid.to_i] = Sample.new(
                  pid: pid.to_i,
                  cpu_percent: cpu.to_f,
                  mem_percent: mem.to_f,
                  rss_bytes: rss.to_i * 1024
                )
              end
            end

            def run_ps_batch(list)
              runner.ps_batch list
            end

            def run_ps_outsiders
              runner.ps_outsiders
            end

            def runner
              @runner ||= Runner.new
            end
          end
        end
      end
    end
  end
end
