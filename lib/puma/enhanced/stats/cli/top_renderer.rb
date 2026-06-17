# frozen_string_literal: true

require_relative "box"
require_relative "format"
require_relative "host_metrics"

module Puma
  module Enhanced
    module Stats
      module CLI
        # Renders SYSTEM and PROCESSES blocks (shown by default, hidden with +--no-top+).
        #
        # SYSTEM shows host load, CPU, memory, and swap via {HostMetrics}.
        # PROCESSES lists worker (and optional master) PIDs enriched with +ps+.
        class TopRenderer
          # @param options [Options]
          # @param bar [Bar]
          # @param master_pid [Integer, nil]
          # @return [TopRenderer]
          def initialize(options, bar, master_pid: nil) = (@options = options; @bar = bar; @master_pid = master_pid; @host = HostMetrics.read)

          # @param budget [LayoutBudget]
          # @return [String]
          def render_system budget
            box = Box.new budget.cols
            lines = []
            if @host.load
              load = @host.load.map { |value| format("%.2f", value) }.join "   "
              lines << "Load   #{load}        (1 / 5 / 15 min)"
            end
            if @host.cpu&.usage
              cpu = @host.cpu
              bar, = @bar.render cpu.usage, width: budget.bar_width, backlog: false
              usage_label = format "%3.0f%%", cpu.usage * 100
              lines << "CPU    usr #{cpu.usr}%  sys #{cpu.sys}%  idle #{cpu.idle}%  [#{bar}] #{usage_label}"
            end
            if @host.memory&.total
              mem = @host.memory
              bar, = @bar.render mem.ratio, width: budget.bar_width, backlog: false
              mem_label = format "%3.0f%%", mem.ratio * 100
              lines << "Memory #{Format.bytes(mem.used)} / #{Format.bytes(mem.total)}  [#{bar}] #{mem_label}"
            end
            if @host.swap&.total&.positive?
              swap = @host.swap
              bar, = @bar.render swap.ratio, width: budget.bar_width, backlog: false
              swap_label = format "%3.0f%%", swap.ratio * 100
              lines << "Swap   #{Format.bytes(swap.used)} / #{Format.bytes(swap.total)}  [#{bar}] #{swap_label}"
            end
            lines = ["Host metrics unavailable on this machine"] if lines.empty?
            box.draw title: "SYSTEM ─ #{Format.hostname}", lines: lines
          end

          # @param payload [Hash{Symbol => Object}]
          # @param budget [LayoutBudget]
          # @param refresh_interval [Integer]
          # @return [String]
          def render_processes payload, budget, refresh_interval:
            workers = payload[:workers] || []
            rows = process_rows workers
            rows = sort_rows rows
            headers = %w[PID %CPU %MEM RSS RUN/CAP BACKLOG POOL W#]
            table_rows = rows.map do |row|
              [
                row[:pid], row[:cpu], row[:mem], row[:rss],
                row[:run_cap], row[:backlog], row[:pool], row[:worker_index]
              ]
            end
            widths = Format.column_widths [headers] + table_rows
            lines = [Format.table_row(headers, widths)]
            table_rows.each { |row| lines << Format.table_row(row, widths) }
            title = "PROCESSES ─ sorted by #{@options.sort}"
            subtitle = "refresh #{refresh_interval}s"
            Box.new(budget.cols).draw title: "#{title} ─ #{subtitle}", lines: lines
          end

          private

          def process_rows workers
            rows = workers.map { |worker| worker_row worker }
            rows << master_row if @master_pid
            enrich_with_ps rows
          end

          def worker_row worker
            puma = worker[:puma] || {}
            process = worker[:process] || {}
            {
              pid: worker[:pid],
              cpu: process[:cpu_percent] || "-",
              mem: "-",
              rss: process[:rss_bytes] ? Format.bytes(process[:rss_bytes]) : "-",
              run_cap: "#{puma[:running]}/#{puma[:pool_capacity]}",
              backlog: puma[:backlog] || "-",
              pool: puma[:pool_capacity] || "-",
              worker_index: worker[:index],
              sort_cpu: process[:cpu_percent].to_f,
              sort_rss: process[:rss_bytes].to_i,
              sort_backlog: puma[:backlog].to_i,
              sort_index: worker[:index].to_i
            }
          end

          def master_row
            {
              pid: @master_pid,
              cpu: "-",
              mem: "-",
              rss: "-",
              run_cap: "-",
              backlog: "-",
              pool: "-",
              worker_index: "M",
              sort_cpu: 0.0,
              sort_rss: 0,
              sort_backlog: 0,
              sort_index: -1
            }
          end

          def enrich_with_ps rows
            pids = rows.map { |row| row[:pid] }.compact
            return rows if pids.empty?

            ps_data = ps_lookup pids
            rows.map do |row|
              stats = ps_data[row[:pid]]
              next row unless stats

              row.merge(
                cpu: stats[:cpu] || row[:cpu],
                mem: stats[:mem] || row[:mem],
                rss: stats[:rss] || row[:rss],
                sort_cpu: stats[:cpu].to_f,
                sort_rss: stats[:rss_bytes].to_i
              )
            end
          end

          def ps_lookup pids
            list = pids.join ","
            output = `ps -o pid=,pcpu=,pmem=,rss= -p #{list} 2>/dev/null`
            output.each_line.with_object({}) do |line, hash|
              pid, cpu, mem, rss = line.strip.split(/\s+/, 4)
              hash[pid.to_i] = {
                cpu: cpu, mem: mem, rss: Format.bytes(rss.to_i * 1024), rss_bytes: rss.to_i * 1024
              }
            end
          rescue StandardError
            {}
          end

          def sort_rows rows
            key = @options.sort.to_s
            rows.sort_by do |row|
              case key
              when "cpu" then [-row[:sort_cpu].to_f, row[:sort_index].to_i]
              when "rss" then [-row[:sort_rss].to_i, row[:sort_index].to_i]
              when "backlog" then [-row[:sort_backlog].to_i, row[:sort_index].to_i]
              else [row[:sort_index].to_i]
              end
            end
          end
        end
      end
    end
  end
end
