# frozen_string_literal: true

require "optparse"
require "json"

module Puma
  module Enhanced
    module Stats
      module CLI
        # Parses CLI flags, fetches enhanced-stats JSON, and renders the dashboard.
        #
        # Invoked by +exe/puma-enhanced-stats+ via {.run}. Supports one-shot output,
        # +--json+ mode, and +--watch+ refresh loops with SIGWINCH redraw.
        #
        # @see Options
        # @see Fetcher
        # @see DashboardRenderer
        class Runner
          class << self
            # @param argv [Array<String>] command-line arguments (typically +ARGV+)
            # @return [Integer] exit code (+0+ success, +1+ on fetch/parse errors)
            def run argv
              new.run argv
            end
          end

          # @param argv [Array<String>] command-line arguments
          # @return [Integer] exit code
          def run argv
            options = parse argv
            fetcher = Fetcher.new options
            payload = fetcher.fetch
            return print_json payload if options.json_mode?

            HostMetrics.reset_cpu_sample!
            HostMetrics.read
            run_dashboard options, fetcher, payload
          rescue Fetcher::Error => e
            warn "error: #{e.message}"
            1
          rescue Interrupt
            0
          end

          private

          # @param argv [Array<String>]
          # @return [Options]
          def parse argv
            options = Options.new
            parser = OptionParser.new do |opts|
              opts.banner = "Usage: puma-enhanced-stats [options]"
              opts.on("-S", "--state PATH", "Puma state file") { |value| options.state_path = value }
              opts.on("-C", "--control-url URL", "Control URL (tcp:// or http://)") { |value| options.control_url = value }
              opts.on("--url URL", "HTTP control URL") { |value| options.url = value }
              opts.on("-T", "--token TOKEN", "Control app auth token") { |value| options.token = value }
              opts.on("-w", "--watch", "Auto-refresh using sync_interval from server") { options.watch = true }
              opts.on("--top", "Show SYSTEM and PROCESSES blocks") { options.top = true }
              opts.on("--json", "Print raw JSON") { options.json_mode = true }
              opts.on("--no-color", "Disable ANSI colors") { options.no_color = true }
              opts.on("--worker N", Integer, "Filter single worker index") { |value| options.worker = value }
              opts.on("--compact", "Compact 2-column worker grid (max 2 workers)") { options.compact = true }
              opts.on("--sort FIELD", "Sort by cpu, rss, backlog, or index") { |value| options.sort = value }
              opts.on("--width COLS", Integer, "Fixed terminal width (tests/CI)") { |value| options.width = value }
              opts.on("-h", "--help", "Show help") do
                puts opts
                exit 0
              end
            end
            parser.parse! argv
            options
          end

          # @param payload [Hash] enhanced-stats JSON
          # @return [Integer] always +0+
          def print_json payload
            puts JSON.pretty_generate payload
            0
          end

          # @param options [Options]
          # @param fetcher [Fetcher]
          # @param initial_payload [Hash]
          # @return [Integer]
          def run_dashboard options, fetcher, initial_payload
            Terminal.trap_winch! if options.watch?
            payload = initial_payload
            interval = sync_interval payload
            deadline = Process.clock_gettime Process::CLOCK_MONOTONIC

            loop do
              now = Process.clock_gettime Process::CLOCK_MONOTONIC
              poll_due = now >= deadline
              if poll_due
                payload = fetcher.fetch
                interval = sync_interval payload
                deadline = now + interval
                HostMetrics.read if options.top?
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

          # @param options [Options]
          # @param fetcher [Fetcher]
          # @param payload [Hash]
          # @param interval [Integer] refresh interval in seconds
          # @return [String] full dashboard frame
          def render_frame options, fetcher, payload, interval
            rows, cols = Terminal.size
            cols = options.width || cols
            workers = payload["workers"] || []
            budget = LayoutBudget.new rows, cols, options, worker_count: workers.size
            colors = Colors.new options
            bar = Bar.new colors
            dashboard = DashboardRenderer.new options, colors, bar
            parts = [dashboard.render_header(payload, budget)]
            if options.top?
              top = TopRenderer.new options, colors, bar, master_pid: fetcher.master_pid
              parts << top.render_system(budget)
              parts << top.render_processes(payload, budget, refresh_interval: interval)
            end
            parts << dashboard.render_body(payload, budget, refresh_interval: interval)
            parts.compact.join "\n\n"
          end

          # @param payload [Hash]
          # @return [Integer] seconds between polls (+5+ when meta is missing)
          def sync_interval payload
            value = payload.dig "meta", "sync_interval_seconds"
            interval = value.to_i
            interval.positive? ? interval : 5
          end
        end
      end
    end
  end
end
