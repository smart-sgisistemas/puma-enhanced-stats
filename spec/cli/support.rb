# frozen_string_literal: true

require "json"
require "puma/enhanced/stats/cli"

module PumaEnhancedStats
  module CLISpecHelpers
    module_function

    def mixed_payload
      JSON.parse File.read(File.expand_path("../fixtures/stub/mixed-cluster.json", __dir__))
    end

    def render_dashboard(width:, request_display: "auto", frame_layout: "stacked", no_color: true, no_top: true)
      Puma::Enhanced::Stats::CLI::Terminal.tty_override = false
      options = Puma::Enhanced::Stats::CLI::Options.new
      options.no_watch = true
      options.no_top = no_top
      options.no_color = no_color
      options.width = width
      options.request_display = request_display.to_s
      options.frame_layout = frame_layout.to_s
      options.frame_layout = "compact" if frame_layout == :compact

      payload = mixed_payload
      view = Puma::Enhanced::Stats::CLI::PayloadView.wrap(payload)
      scroll = Puma::Enhanced::Stats::CLI::ScrollState.new
      rows, cols = 40, width
      workers = view.workers
      layout = Puma::Enhanced::Stats::CLI::LayoutRegistry.resolve(
        options,
        Puma::Enhanced::Stats::CLI::LayoutBudget.new(rows, cols, options, worker_count: workers.size),
        mode: view.mode
      )
      budget = Puma::Enhanced::Stats::CLI::LayoutBudget.new(
        rows, cols, options, worker_count: workers.size,
        layout: layout.layout, saved_layout: layout.saved_layout
      )
      process_by_pid = stub_process_samples(workers)
      host = Puma::Enhanced::Stats::CLI::HostMetrics::EMPTY
      attribution = Puma::Enhanced::Stats::CLI::ResourceAttribution.compute(
        host: host, puma_pids: process_by_pid.keys,
        process_by_pid: process_by_pid, degraded: false
      )
      colors = Puma::Enhanced::Stats::CLI::Colors.new options
      bar = Puma::Enhanced::Stats::CLI::Bar.new colors
      Puma::Enhanced::Stats::CLI::FrameRenderer.new(options, budget, bar, colors).render(
        payload, host: host, process_by_pid: process_by_pid,
        attribution: attribution, scroll: scroll, interval: 5, master_pid: 48_200
      )
    ensure
      Puma::Enhanced::Stats::CLI::Terminal.tty_override = nil
    end

    def mixed_workers
      Puma::Enhanced::Stats::CLI::PayloadView.wrap(mixed_payload).workers
    end

    def mixed_view
      Puma::Enhanced::Stats::CLI::PayloadView.wrap(mixed_payload)
    end

    def stub_process_samples(workers)
      workers.each_with_object({}) do |worker, hash|
        pid = worker["pid"]
        hash[pid] = Puma::Enhanced::Stats::CLI::ProcessSampler::Sample.new(
          pid: pid, cpu_percent: 18.0, mem_percent: 2.5, rss_bytes: 128_000_000
        )
      end.merge(48_200 => Puma::Enhanced::Stats::CLI::ProcessSampler::Sample.new(
        pid: 48_200, cpu_percent: 0.3, mem_percent: 0.8, rss_bytes: 128_000_000
      ))
    end
  end
end

RSpec.configure do |config|
  config.include PumaEnhancedStats::CLISpecHelpers, file_path: %r{spec/cli/}
end
