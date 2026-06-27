# frozen_string_literal: true

require "optparse"
require "json"

module Puma
  module Enhanced
    module Stats
      module CLI
        # Entry point for the +puma-enhanced-stats+ executable.
        class Runner
          WATCH_HELP_NOTE = "In watch mode, press ? for field reference."

          class << self
            def run(argv) = new.run(argv)
          end

          def run(argv)
            @options = parse argv
            @fetcher = Fetcher.new(overrides: @options.connection_overrides)
            @scroll = ScrollState.new
            @screen = ScreenManager.new @options
            payload = @fetcher.fetch
            return print_json payload if @options.json

            prime_host_metrics! if @options.top?
            @options.watch? ? run_watch(payload) : run_once(payload)
          rescue Fetcher::Error => e
            warn "error: #{e.message}"
            1
          rescue Interrupt
            0
          ensure
            Terminal.restore!
          end

          private

          def parse(argv)
            options = Options.new
            UserConfig.apply!(options, UserConfig.load) unless argv.include? "--no-rc"

            OptionParser.new do |opts|
              opts.banner = "Usage: puma-enhanced-stats [options]"
              opts.separator ""
              opts.separator "Connection  pumactl style:"
              opts.on("-S", "--state PATH", "Puma state file") { |v| options.state_path = v }
              opts.on("-C", "--control-url URL", "Control app URL") { |v| options.control_url = v }
              opts.on("-T", "--token TOKEN", "Control app auth token") { |v| options.token = v }
              opts.on("-F", "--config PATH", "Puma config file") { |v| options.config_path = v }
              opts.separator ""
              opts.on("--no-watch", "Single snapshot, stdout") { options.no_watch = true }
              opts.on("--no-top", "Hide TOP and PROCESSES blocks") { options.no_top = true }
              opts.on("--sort FIELD", "Sort: severity, cpu, rss, backlog, index") { |v| options.sort_process = v }
              opts.on("--no-color", "Disable ANSI colors") { options.no_color = true }
              opts.on("--json", "Print raw JSON") { options.json = true }
              opts.on("--filter", "FIELD=VALUE", "Request filter  repeatable") do |v|
                next unless v.is_a?(String)

                field, value = v.split "=", 2
                options.filters[field] = value if field && value
              end
              opts.on("--layout MODE", "Frame layout") { |v| options.frame_layout = v }
              opts.on("--request-display MODE", "auto, inline, stack") { |v| options.request_display = v }
              opts.on("--no-rc", "Ignore ~/.pesrc") { options.no_rc = true }
              opts.on("-w", "--width COLS", Integer, "Fixed width") { |v| options.width = v }
              opts.on("-h", "--help", "Show help") do
                puts opts
                puts ""
                puts WATCH_HELP_NOTE
                exit 0
              end
            end.parse! argv
            options
          end

          def run_once(payload)
            print render_frame payload
            print "\n"
            0
          end

          def run_watch(initial_payload)
            Terminal.enter_alternate_screen! if Terminal.tty?
            Terminal.trap_winch!
            payload = initial_payload
            interval = poll_interval payload
            deadline = monotonic

            loop do
              now = monotonic
              poll_due = now >= deadline || @options.force_refresh
              if poll_due
                payload = @fetcher.fetch
                @scroll.clamp! payload
                interval = poll_interval payload
                deadline = now + interval
                @options.force_refresh = false
              end

              print_frame payload, interval

              while monotonic < deadline
                while Keyboard.refresh?
                  key = Keyboard.read deadline: deadline
                  break unless key

                  @screen.handle key, scroll: @scroll, payload: payload
                  @options.force_refresh = true if @options.dirty
                end
                sleep 0.05
                break if Terminal.resize_pending
              end
              Terminal.reset_resize!
            end
            0
          rescue Interrupt
            0
          end

          def print_frame(payload, interval)
            frame = render_frame payload, interval: interval
            if Terminal.tty?
              Terminal.clear
              $stdout.print frame
              $stdout.print "\e[J"
            else
              print frame
              print "\n" unless frame.end_with? "\n"
            end
          end

          def prime_host_metrics!
            return unless @options.top?

            HostMetrics.reset_cpu_sample!
            HostMetrics.read
          end

          def render_frame(payload, interval: 5)
            return @screen.render_modal budget_for payload if @screen.modal_open?

            rows, cols = Terminal.size
            cols = @options.width || cols
            workers = payload["workers"] || []
            layout = LayoutRegistry.resolve(
              @options,
              LayoutBudget.new(rows, cols, @options, worker_count: workers.size)
            )
            budget = LayoutBudget.new(
              rows, cols, @options, worker_count: workers.size,
              layout: layout.layout, saved_layout: layout.saved_layout
            )
            budget.warnings << layout.hint if layout.hint

            host = @options.top? ? HostMetrics.read : HostMetrics::EMPTY
            process_by_pid = ProcessSampler.sample_all workers, master_pid: @fetcher.master_pid
            attribution = build_attribution host, process_by_pid
            colors = Colors.new @options
            bar = Bar.new colors
            FrameRenderer.new(@options, budget, bar, colors).render(
              payload, host: host, process_by_pid: process_by_pid,
              attribution: attribution, scroll: @scroll, interval: interval,
              master_pid: @fetcher.master_pid
            )
          end

          def budget_for(payload)
            rows, cols = Terminal.size
            cols = @options.width || cols
            LayoutBudget.new(rows, cols, @options, worker_count: (payload["workers"] || []).size)
          end

          def build_attribution(host, process_by_pid)
            puma_pids = process_by_pid.keys
            degraded = !process_by_pid.empty? && process_by_pid.values.all? { |s| s.cpu_percent.nil? }
            attribution = ResourceAttribution.compute(
              host: host, puma_pids: puma_pids,
              process_by_pid: process_by_pid, degraded: degraded
            )
            if @options.show_outsiders? || attribution.warn_or_crit?
              attribution.load_outsiders! exclude_pids: puma_pids
            end
            attribution
          end

          def poll_interval(payload)
            value = payload.dig("meta", "worker_check_interval_seconds").to_i
            value.positive? ? value : 5
          end

          def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)

          def print_json(payload) = (puts JSON.pretty_generate(payload); 0)
        end
      end
    end
  end
end
