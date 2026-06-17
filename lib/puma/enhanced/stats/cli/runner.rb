# frozen_string_literal: true

require "optparse"
require "json"

module Puma
  module Enhanced
    module Stats
      module CLI
        # Entry point for the +puma-enhanced-stats+ executable.
        #
        # Parses flags, fetches JSON from the control app, and renders either a
        # full dashboard or raw JSON. {Fetcher::Error} and +Interrupt+ map to
        # exit codes +1+ and +0+ respectively.
        class Runner
          class << self
            # @param argv [Array<String>]
            # @return [Integer] exit code
            def run(argv) = new.run(argv)
          end

          # @param argv [Array<String>]
          # @return [Integer] exit code
          def run argv
            options = parse argv
            fetcher = Fetcher.new
            payload = fetcher.fetch
            return print_json payload if options.json

            unless options.request_only
              HostMetrics.reset_cpu_sample!
              HostMetrics.read if options.top?
            end
            run_dashboard options, fetcher, payload
          rescue Fetcher::Error => e
            warn "error: #{e.message}"
            1
          rescue Interrupt
            0
          end

          private

          def parse argv
            options = Options.new
            parser = OptionParser.new do |opts|
              opts.banner = "Usage: puma-enhanced-stats [options]"
              opts.on("-T", "--no-top", "Hide SYSTEM and PROCESSES blocks") { options.no_top = true }
              opts.on("-C", "--no-color", "Disable ANSI colors") { options.no_color = true }
              opts.on("-W", "--no-watch", "Print one snapshot and exit") { options.no_watch = true }
              opts.on("--request-only", "Show worker summary and in-flight requests only") do
                options.request_only = true
              end
              opts.on("--json", "Print raw JSON") { options.json = true }
              opts.on("--worker N", Integer, "Filter single worker index") { |value| options.worker = value }
              opts.on("--compact", "Compact 2-column worker grid (max 2 workers)") { options.compact = true }
              opts.on("-s", "--sort FIELD", "Sort by cpu, rss, backlog, or index") { |value| options.sort = value }
              opts.on("-w", "--width COLS", Integer, "Fixed terminal width (tests/CI)") { |value| options.width = value }
              opts.on("-h", "--help", "Show help") do
                puts opts
                exit 0
              end
            end
            parser.parse! argv
            options
          end

          def print_json(payload) = (puts JSON.pretty_generate(payload); 0)

          def run_dashboard options, fetcher, initial_payload
            Terminal.trap_winch! if options.watch?
            payload = initial_payload
            interval = worker_check_interval payload
            deadline = Process.clock_gettime Process::CLOCK_MONOTONIC

            loop do
              now = Process.clock_gettime Process::CLOCK_MONOTONIC
              poll_due = now >= deadline
              if poll_due
                payload = fetcher.fetch
                interval = worker_check_interval payload
                deadline = now + interval
                HostMetrics.read if options.top? && !options.request_only
              end

              frame = render_frame options, fetcher, payload, interval
              Terminal.clear if options.watch? && Terminal.tty?
              print frame
              print "\n" unless frame.end_with? "\n"

              break unless options.watch?

              Terminal.reset_resize!
              sleep 0.2 until poll_due ||
                             Terminal.resize_pending ||
                             Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
            end
            0
          end

          def render_frame options, fetcher, payload, interval
            rows, cols = Terminal.size
            cols = options.width || cols
            workers = payload[:workers] || []
            budget = LayoutBudget.new rows, cols, options, worker_count: workers.size
            colors = Colors.new options

            if options.request_only
              return RequestOnlyRenderer.new(options).render(
                payload, budget, refresh_interval: interval
              )
            end

            bar = Bar.new colors
            dashboard = DashboardRenderer.new options, bar
            parts = [dashboard.render_header(payload, budget)]
            if options.top?
              top = TopRenderer.new options, bar, master_pid: fetcher.master_pid
              parts << top.render_system(budget)
              parts << top.render_processes(payload, budget, refresh_interval: interval)
            end
            parts << dashboard.render_body(payload, budget, refresh_interval: interval)
            parts.compact.join "\n\n"
          end

          def worker_check_interval(payload)
            value = payload.dig :meta, :worker_check_interval_seconds
            interval = value.to_i
            interval.positive? ? interval : 5
          end
        end
      end
    end
  end
end
