# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module CLI
        # TOP and PROCESSES blocks.
        class TopRenderer
          def initialize(options, bar, host:, attribution:, colors: nil, master_pid: nil, process_by_pid: {})
            @options = options
            @bar = bar
            @colors = colors
            @host = host
            @attribution = attribution
            @master_pid = master_pid
            @process_by_pid = process_by_pid
          end

          def box_spec_top(budget)
            Box::Spec.new(title: "TOP ─ #{Format.hostname}", lines: top_lines(budget.metric_content_width))
          end

          def box_spec_processes(payload, refresh_interval:, budget: nil)
            inner = budget ? LayoutGrid.content_width(budget.box_cols) : nil
            Box::Spec.new(
              title: processes_title(refresh_interval),
              lines: processes_lines(payload, max_width: inner)
            )
          end

          def render_top(budget)
            spec = box_spec_top budget
            budget.make_box.draw title: spec.title, lines: spec.lines
          end

          def render_processes(payload, budget, refresh_interval:)
            spec = box_spec_processes payload, refresh_interval: refresh_interval, budget: budget
            budget.make_box.draw title: spec.title, lines: spec.lines
          end

          private

          def top_lines(content_width)
            lines = []
            if @host.load
              load = @host.load.map { |v| format "%.2f", v }.join "   "
              lines << "Load   #{load}        (1 / 5 / 15 min)"
            end
            if @host.cpu && !@host.cpu.usage.nil?
              lines.concat cpu_host_lines(@host.cpu, content_width)
            end
            if @host.memory&.total&.positive?
              mem = @host.memory
              suffix = format "%3.0f%%", mem.ratio * 100
              suffix = "#{suffix} #{@attribution.mem_suffix}" if @attribution.mem_suffix
              lines.concat metric_host("Memory", mem.used, mem.total, mem.ratio, suffix, content_width)
            end
            if @host.swap&.total&.positive?
              swap = @host.swap
              suffix = format "%3.0f%%", swap.ratio * 100
              lines.concat metric_host("Swap", swap.used, swap.total, swap.ratio, suffix, content_width)
            end
            lines << @host.memory_limit_hint if @host.memory_limit_hint
            lines = ["Host metrics unavailable"] if lines.empty?
            lines
          end

          def processes_title(refresh_interval)
            "PROCESSES ─ sorted by #{@options.sort_process} ─ refresh #{refresh_interval}s"
          end

          def processes_lines(payload, max_width: nil)
            workers = PayloadView.wrap(payload).workers
            rows = sort_rows process_rows(workers)
            headers = %w[PID %CPU %MEM RSS RUN/CAP BACKLOG POOL W#]
            table_rows = rows.map do |row|
              [row[:pid], row[:cpu], row[:mem], row[:rss], row[:run_cap], row[:backlog], row[:pool], row[:w]]
            end
            widths = Format.column_widths [headers] + table_rows
            lines = [Format.table_row(headers, widths)]
            rows.zip(table_rows).each do |meta, cells|
              line = color_process_row(Format.table_row(cells, widths), meta)
              line = Format.truncate_display(line, max_width) if max_width
              lines << line
            end
            lines
          end

          def cpu_host_lines(cpu, content_width)
            lines = cpu_breakdown_lines(cpu, label: "CPU", content_width: content_width, attribution_suffix: true)
            Array(cpu.cores).each do |core|
              lines.concat cpu_breakdown_lines(
                core, label: "core #{core.index}", content_width: content_width, attribution_suffix: false
              )
            end
            lines
          end

          def cpu_breakdown_lines(cpu, label:, content_width:, attribution_suffix:)
            suffix = format "%3.0f%%", cpu.usage * 100
            suffix = "#{suffix} #{@attribution.cpu_suffix}" if attribution_suffix && @attribution.cpu_suffix
            bar_w = LayoutGrid.bar_width_for(
              content_width,
              value_width: LayoutGrid::HOST_VALUE_WIDTH,
              label_width: LayoutGrid::TOP_LABEL_WIDTH
            )
            bar, = @bar.render cpu.usage, width: bar_w, backlog: false
            LayoutGrid.cpu_breakdown_rows(
              label: label, usr: cpu.usr, sys: cpu.sys, idle: cpu.idle,
              bar: bar, suffix: suffix, content_width: content_width
            )
          end

          def metric_host(label, used, total, ratio, suffix, content_width)
            value = "#{Format.bytes used} / #{Format.bytes total}"
            MetricLine.new(
              label: label, value: value, suffix: suffix, colors: @colors,
              ratio: ratio, bar_renderer: @bar,
              label_width: LayoutGrid::TOP_LABEL_WIDTH,
              value_width: LayoutGrid::HOST_VALUE_WIDTH
            ).render(content_width: content_width)
          end

          def color_process_row(line, meta)
            return line unless @colors
            return line unless meta[:backlog_sort].to_i.positive?

            @colors.paint(line, :crit)
          end

          def process_rows(workers)
            rows = workers.map { |worker| worker_row worker }
            rows << master_row if @master_pid
            rows
          end

          def worker_row(worker)
            puma = worker["puma"] || {}
            sample = @process_by_pid[worker["pid"]]
            degraded = sample.nil? || sample.cpu_percent.nil?
            {
              pid: worker["pid"],
              cpu: degraded ? "—" : format("%.1f", sample.cpu_percent),
              mem: degraded ? "—" : format("%.1f", sample.mem_percent),
              rss: degraded ? "—" : Format.bytes(sample.rss_bytes),
              run_cap: "#{puma['running']}/#{puma['max_threads']}",
              backlog: puma["backlog"] || "-",
              pool: puma["pool_capacity"] || "-",
              w: worker["single"] ? "S" : worker["index"],
              sort_cpu: sample&.cpu_percent.to_f,
              sort_index: worker["index"].to_i,
              backlog_sort: puma["backlog"].to_i
            }
          end

          def master_row
            sample = @process_by_pid[@master_pid]
            {
              pid: @master_pid,
              cpu: sample ? format("%.1f", sample.cpu_percent) : "—",
              mem: sample ? format("%.1f", sample.mem_percent) : "—",
              rss: sample ? Format.bytes(sample.rss_bytes) : "—",
              run_cap: "-", backlog: "-", pool: "-", w: "M",
              sort_cpu: sample&.cpu_percent.to_f, sort_index: -1, backlog_sort: 0
            }
          end

          def sort_rows(rows)
            key = @options.sort_process.to_s
            case key
            when "cpu"
              rows.sort_by { |r| [-r[:sort_cpu].to_f, r[:sort_index]] }
            when "rss"
              rows.sort_by { |r| [-r[:rss].to_s.gsub(/\D/, "").to_i, r[:sort_index]] }
            when "backlog"
              rows.sort_by { |r| [-r[:backlog_sort].to_i, r[:sort_index]] }
            else
              SeveritySorter.sort_process_rows rows
            end
          end
        end
      end
    end
  end
end
