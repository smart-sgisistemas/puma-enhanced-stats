# frozen_string_literal: true

require "puma/enhanced/stats/cli/runner"
require "puma/enhanced/stats/cli/cgroup_memory"
require "puma/enhanced/stats/cli/process_sampler"
require "puma/enhanced/stats/cli/resource_attribution"
require "puma/enhanced/stats/cli/frame_renderer"
require "puma/enhanced/stats/cli/terminal"
require "puma/enhanced/stats/cli/screen_manager"
require "puma/enhanced/stats/cli/user_config"
require "puma/enhanced/stats/cli/options"
require "puma/enhanced/stats/cli/request_sorter"
require "puma/enhanced/stats/cli/metric_line"
require "puma/enhanced/stats/cli/label_line"
require "puma/enhanced/stats/cli/layout_budget"
require "puma/enhanced/stats/cli/sync_freshness"
require "puma/enhanced/stats/cli/top_renderer"
require "puma/enhanced/stats/cli/summary_renderer"
require "puma/enhanced/stats/cli/request_table"
require "puma/enhanced/stats/cli/request_field_catalog"
require "puma/enhanced/stats/cli/severity_sorter"
require "puma/enhanced/stats/cli/worker_renderer"
require "puma/enhanced/stats/cli/footer_renderer"
require "puma/enhanced/stats/cli/stub_server"
require "puma/enhanced/stats/cli/keyboard"

RSpec.describe "CLI final coverage sweep" do
  describe Puma::Enhanced::Stats::CLI::Runner do
    let(:payload) { mixed_payload }
    let(:fetcher) { instance_double(Puma::Enhanced::Stats::CLI::Fetcher, fetch: payload, master_pid: nil) }

    it "sleeps while waiting for the next poll deadline" do
      options = Puma::Enhanced::Stats::CLI::Options.new
      allow(Puma::Enhanced::Stats::CLI::Terminal).to receive(:tty?).and_return false
      allow(Puma::Enhanced::Stats::CLI::Terminal).to receive(:size).and_return [40, 78]
      allow(Puma::Enhanced::Stats::CLI::HostMetrics).to receive(:read).and_return(Puma::Enhanced::Stats::CLI::HostMetrics::EMPTY)
      allow(Puma::Enhanced::Stats::CLI::ProcessSampler).to receive(:sample_all).and_return({})
      allow(Puma::Enhanced::Stats::CLI::Keyboard).to receive(:refresh?).and_return false
      allow(Puma::Enhanced::Stats::CLI::Terminal).to receive(:resize_pending).and_return false

      runner = described_class.new
      runner.instance_variable_set :@options, options
      runner.instance_variable_set :@fetcher, fetcher
      runner.instance_variable_set(:@scroll, Puma::Enhanced::Stats::CLI::ScrollState.new)
      runner.instance_variable_set(:@screen, Puma::Enhanced::Stats::CLI::ScreenManager.new(options))
      allow(runner).to receive(:monotonic).and_return 1000, 1000, 1000.1, 1006
      expect(runner).to receive(:sleep).with(0.05).at_least :once
      allow(runner).to receive(:loop).and_yield
      allow(runner).to receive :print_frame

      expect(runner.send :run_watch, payload).to eq 0
    end
  end

  describe Puma::Enhanced::Stats::CLI::CgroupMemory do
    after { described_class.reset! }

    it "rescues read errors on cgroup and meminfo paths" do
      stub_const "RUBY_PLATFORM", "linux"
      described_class.reset!
      allow(File).to receive(:file?).with("/sys/fs/cgroup/memory.max").and_return false
      allow(File).to receive(:file?).with("/sys/fs/cgroup/memory/memory.limit_in_bytes").and_return true
      allow(File).to receive(:read).with("/sys/fs/cgroup/memory/memory.limit_in_bytes").and_raise StandardError
      allow(File).to receive(:readlines).with("/proc/meminfo").and_raise StandardError
      expect(described_class.total_bytes).to be_nil

      described_class.reset!
      allow(File).to receive(:file?).with("/sys/fs/cgroup/memory.max").and_return false
      allow(File).to receive(:file?).with("/sys/fs/cgroup/memory/memory.limit_in_bytes").and_return true
      allow(File).to receive(:read).with("/sys/fs/cgroup/memory/memory.limit_in_bytes").and_return "4096\n"
      allow(File).to receive(:file?).with("/sys/fs/cgroup/memory.current").and_return false
      allow(File).to receive(:file?).with("/sys/fs/cgroup/memory/memory.usage_in_bytes").and_return true
      allow(File).to receive(:read).with("/sys/fs/cgroup/memory/memory.usage_in_bytes").and_raise StandardError
      expect(described_class.used_bytes).to be_nil

      described_class.reset!
      stub_const "RUBY_PLATFORM", "arm64-darwin23"
      allow(described_class).to receive(:`).with("sysctl -n hw.memsize").and_raise StandardError
      expect(described_class.total_bytes).to be_nil
    end
  end

  describe Puma::Enhanced::Stats::CLI::ProcessSampler::Runner do
    it "invokes ps commands" do
      runner = described_class.new
      allow(runner).to receive(:`).with(/ps -o pid=/).and_return "1 1 1 1\n"
      allow(runner).to receive(:`).with(/ps -eo/).and_return "9 1 1 1 other\n"
      expect(runner.ps_batch "1").to include "1"
      expect(runner.ps_outsiders).to include "9"
    end
  end

  describe Puma::Enhanced::Stats::CLI::ProcessSampler do
    it "memoizes the runner instance" do
      described_class.send :remove_instance_variable, :@runner if described_class.instance_variable_defined? :@runner
      first = described_class.send :runner
      second = described_class.send :runner
      expect(first).to equal second
    end
  end

  describe Puma::Enhanced::Stats::CLI::FrameRenderer do
    it "returns empty worker sections for filtered focus and compact layouts" do
      options = Puma::Enhanced::Stats::CLI::Options.new
      options.frame_layout = "focus"
      options.focus_worker = 99
      options.no_color = true
      payload = mixed_payload
      budget = Puma::Enhanced::Stats::CLI::LayoutBudget.new(40, 80, options, worker_count: 3, layout: "focus")
      colors = Puma::Enhanced::Stats::CLI::Colors.new options
      bar = Puma::Enhanced::Stats::CLI::Bar.new colors
      renderer = described_class.new options, budget, bar, colors
      sections = renderer.send(
        :worker_sections, payload, {}, Puma::Enhanced::Stats::CLI::ScrollState.new, 5, "focus"
      )
      expect(sections).to eq []

      options.frame_layout = "compact"
      budget = Puma::Enhanced::Stats::CLI::LayoutBudget.new(40, 80, options, worker_count: 0, layout: "compact")
      renderer = described_class.new options, budget, bar, colors
      sections = renderer.send(
        :worker_sections, payload.merge("workers" => []), {}, Puma::Enhanced::Stats::CLI::ScrollState.new, 5, "compact"
      )
      expect(sections).to eq []
    end

    it "shows outsiders when configured" do
      options = Puma::Enhanced::Stats::CLI::Options.new
      options.show_outsiders = true
      budget = Puma::Enhanced::Stats::CLI::LayoutBudget.new(40, 120, options, worker_count: 2, layout: "stacked")
      attribution = Puma::Enhanced::Stats::CLI::ResourceAttribution.compute(
        host: Puma::Enhanced::Stats::CLI::HostMetrics::EMPTY, puma_pids: [], process_by_pid: {}
      )
      attribution.result.outsiders.replace([
        Puma::Enhanced::Stats::CLI::ProcessSampler::Outsider.new(
          pid: 9, cpu_percent: 1, mem_percent: 1, rss_bytes: 1, command: "ruby"
        )
      ])
      renderer = described_class.new(
        options, budget, Puma::Enhanced::Stats::CLI::Bar.new(Puma::Enhanced::Stats::CLI::Colors.new(options)),
        Puma::Enhanced::Stats::CLI::Colors.new(options)
      )
      expect(renderer.send :show_outsiders?, attribution).to be true
    end
  end

  describe Puma::Enhanced::Stats::CLI::ScreenManager do
    it "handles modal noop keys and empty worker scroll targets" do
      options = Puma::Enhanced::Stats::CLI::Options.new
      options.modal = :sort
      manager = described_class.new options
      scroll = Puma::Enhanced::Stats::CLI::ScrollState.new
      expect(manager.handle("z", scroll: scroll, payload: { "workers" => [] })).to be true

      options.modal = nil
      expect(manager.handle("j", scroll: scroll, payload: { "workers" => [] })).to be true
      options.frame_layout = "unknown"
      manager.send :cycle_layout!
      expect(Puma::Enhanced::Stats::CLI::FrameRenderer::LAYOUTS).to include(options.frame_layout)
    end
  end

  describe Puma::Enhanced::Stats::CLI::Terminal do
    after do
      described_class.size_override = nil
      described_class.tty_override = nil
      described_class.alternate_active = false
    end

    it "rescues winsize failures and skips winch when unavailable" do
      described_class.tty_override = true
      console = instance_double IO
      allow(IO).to receive(:console).and_return console
      allow(console).to receive(:winsize).and_raise StandardError
      expect(described_class.size).to eq [24, 80]

      hide_const("Signal::LIST") if defined?(Signal::LIST)
      stub_const("Signal::LIST", {})
      expect(described_class.trap_winch!).to be_nil
      described_class.alternate_active = false
      described_class.leave_alternate_screen!
    end
  end

  describe "remaining CLI branch helpers" do
    it "covers truthy fallbacks, sorters, lines, budgets, sync, top, summary, table, footer" do
      expect(Puma::Enhanced::Stats::CLI::UserConfig.send :truthy?, "maybe").to be true
      expect(Puma::Enhanced::Stats::CLI::Options.new.tap { |o| o.show_top = "maybe" }.show_top?).to be true

      expect(Puma::Enhanced::Stats::CLI::RequestSorter.send :sort_key, { "x" => nil }, "x").to eq ""

      colors = Puma::Enhanced::Stats::CLI::Colors.new(Puma::Enhanced::Stats::CLI::Options.new.tap { |o| o.no_color = true })
      expect(Puma::Enhanced::Stats::CLI::MetricLine.new(
        label: "a", value: "1", bar: "#", suffix: "\e[31mWARN\e[0m", colors: colors
      ).render.join).to include "\e"
      expect(Puma::Enhanced::Stats::CLI::LabelLine.new(
        label: "b", value: "2", badge: "\e[33mINFO\e[0m", colors: nil
      ).render.join).to include "\e"

      options = Puma::Enhanced::Stats::CLI::Options.new
      options.show_outsiders = true
      budget = Puma::Enhanced::Stats::CLI::LayoutBudget.new(40, 120, options, worker_count: 2, layout: "compact")
      expect(budget.available_for_workers).to be > 0
      expect(budget.request_display_mode).to eq "inline"

      expect(Puma::Enhanced::Stats::CLI::SyncFreshness.evaluate(
        synced_at: "2026-01-01T00:00:04Z", collected_at: "", interval_seconds: 5, mode: "cluster"
      ).badge).to eq :ok

      host = Puma::Enhanced::Stats::CLI::HostMetrics::Snapshot.new(
        load: [0.1], cpu: nil, memory: nil, swap: nil, memory_limit_hint: nil
      )
      attribution = Puma::Enhanced::Stats::CLI::ResourceAttribution.compute(
        host: host, puma_pids: [1, 2], process_by_pid: { 1 => nil }, degraded: false
      )
      expect(attribution.puma_cpu).to eq 0.0

      top = Puma::Enhanced::Stats::CLI::TopRenderer.new(
        options, Puma::Enhanced::Stats::CLI::Bar.new(colors),
        host: host, attribution: attribution, process_by_pid: {}
      )
      payload = { "workers" => [{ "index" => 0, "pid" => 1, "puma" => { "running" => 0, "max_threads" => 5, "backlog" => 0, "pool_capacity" => 0 } }] }
      expect(top.send(:sort_rows, [{ sort_cpu: 1, sort_index: 0, backlog_sort: 0, rss: "1", backlog: 0 }])).not_to be_empty

      summary = Puma::Enhanced::Stats::CLI::SummaryRenderer.new(
        Puma::Enhanced::Stats::CLI::Bar.new(colors), colors
      )
      warn_attr = Puma::Enhanced::Stats::CLI::ResourceAttribution.compute(
        host: Puma::Enhanced::Stats::CLI::HostMetrics::Snapshot.new(
          load: nil,
          cpu: Puma::Enhanced::Stats::CLI::HostMetrics::CPU.new(usr: 0, sys: 0, idle: 0, usage: 0.8),
          memory: Puma::Enhanced::Stats::CLI::HostMetrics::Usage.new(used: 1, total: 2, ratio: 0.8),
          swap: Puma::Enhanced::Stats::CLI::HostMetrics::Usage.new(used: 0, total: 1, ratio: 0),
          memory_limit_hint: nil
        ),
        puma_pids: [1],
        process_by_pid: {
          1 => Puma::Enhanced::Stats::CLI::ProcessSampler::Sample.new(pid: 1, cpu_percent: 10, mem_percent: 1, rss_bytes: 100)
        }
      )
      output = summary.render(
        mixed_payload.merge("summary" => mixed_payload["summary"].merge("workers_stale" => 0, "workers_reporting" => 3)),
        budget,
        attribution: warn_attr
      )
      expect(output).to include "Host vs Puma"

      items = [{ "id" => "1", "started_at" => "t", "elapsed_ms" => 1, "method" => "GET", "path_info" => "/" * 200, "session" => {} }] * 2
      table = Puma::Enhanced::Stats::CLI::RequestTable.new(items, inner_width: 30, display_mode: "inline", offset: 0)
      expect(table.render(max_items: 1).join "\n").to include "more requests"

      expect(Puma::Enhanced::Stats::CLI::RequestFieldCatalog.discover [{ "id" => "1", "started_at" => "t", "session" => {} }]).to include "id"

      workers = [
        { "index" => 0, "pid" => 1, "synced_at" => "2026-01-01T00:00:00Z", "puma" => { "backlog" => 0 }, "requests" => { "items" => [{ "id" => "1" }], "meta" => { "request_limit" => 2 } } },
        { "index" => 1, "pid" => 2, "synced_at" => nil, "puma" => { "backlog" => 2 }, "requests" => { "items" => [], "meta" => { "request_limit" => 2 } } }
      ]
      sorted = Puma::Enhanced::Stats::CLI::SeveritySorter.sort_workers(
        workers, process_by_pid: { 1 => nil, 2 => nil }, interval: 5, mode: "cluster", collected_at: "2026-01-01T00:00:10Z"
      )
      expect(sorted.first["index"]).to eq 1

      expect(Puma::Enhanced::Stats::CLI::FooterRenderer.new.render(
        options, budget, refresh_interval: 5, layout_hint: "hint"
      )).to include "hint"

      server = Puma::Enhanced::Stats::CLI::StubServer.new(port: 0, token: nil, payload: {})
      socket = instance_double(TCPSocket, close: nil)
      allow(socket).to receive(:gets).and_return "GET /enhanced-stats HTTP/1.1\r\n", "\r\n"
      allow(socket).to receive(:write) { |body| expect(body).to include "200" }
      server.send :handle, socket

      allow(Puma::Enhanced::Stats::CLI::Terminal).to receive(:tty?).and_return true
      allow(IO).to receive(:select).and_return nil
      expect(Puma::Enhanced::Stats::CLI::Keyboard.refresh?).to be false
    end
  end
end
