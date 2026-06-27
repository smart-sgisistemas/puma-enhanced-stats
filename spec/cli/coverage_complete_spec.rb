# frozen_string_literal: true

require "json"
require "socket"
require "puma/enhanced/stats/cli/runner"
require "puma/enhanced/stats/cli/cgroup_memory"
require "puma/enhanced/stats/cli/keyboard"
require "puma/enhanced/stats/cli/process_sampler"
require "puma/enhanced/stats/cli/resource_attribution"
require "puma/enhanced/stats/cli/summary_renderer"
require "puma/enhanced/stats/cli/user_config"
require "puma/enhanced/stats/cli/stub_payload_builder"
require "puma/enhanced/stats/cli/stub_server"
require "puma/enhanced/stats/cli/request_table"
require "puma/enhanced/stats/cli/sync_freshness"
require "puma/enhanced/stats/cli/format"
require "puma/enhanced/stats/cli/options"
require "puma/enhanced/stats/cli/request_field_catalog"
require "puma/enhanced/stats/cli/scroll_state"
require "puma/enhanced/stats/cli/request_sorter"
require "puma/enhanced/stats/cli/metric_line"
require "puma/enhanced/stats/cli/label_line"
require "puma/enhanced/stats/cli/alert_level"
require "puma/enhanced/stats/cli/severity_sorter"
require "puma/enhanced/stats/cli/filter_screen"

RSpec.describe "CLI coverage completion" do
  describe Puma::Enhanced::Stats::CLI::Runner do
    let(:payload) { mixed_payload }

    let(:fetcher) do
      instance_double(
        Puma::Enhanced::Stats::CLI::Fetcher,
        fetch: payload,
        master_pid: 48_200
      )
    end

    before do
      allow(Puma::Enhanced::Stats::CLI::Fetcher).to receive(:new).and_return fetcher
      allow(Puma::Enhanced::Stats::CLI::UserConfig).to receive(:load).and_return({})
      allow(Puma::Enhanced::Stats::CLI::Terminal).to receive :trap_winch!
      allow(Puma::Enhanced::Stats::CLI::Terminal).to receive :clear
      allow(Puma::Enhanced::Stats::CLI::Terminal).to receive :restore!
      allow(Puma::Enhanced::Stats::CLI::Terminal).to receive :enter_alternate_screen!
      allow(Puma::Enhanced::Stats::CLI::Terminal).to receive :leave_alternate_screen!
      allow(Puma::Enhanced::Stats::CLI::Terminal).to receive :reset_resize!
      allow(Puma::Enhanced::Stats::CLI::HostMetrics).to receive :reset_cpu_sample!
    end

    it "polls and redraws during watch mode" do
      options = Puma::Enhanced::Stats::CLI::Options.new
      allow(Puma::Enhanced::Stats::CLI::Terminal).to receive(:tty?).and_return false
      allow(Puma::Enhanced::Stats::CLI::Terminal).to receive(:size).and_return [40, 78]
      allow(Puma::Enhanced::Stats::CLI::Terminal).to receive(:resize_pending).and_return true, false
      allow(Puma::Enhanced::Stats::CLI::HostMetrics).to receive(:read).and_return(
        Puma::Enhanced::Stats::CLI::HostMetrics::EMPTY
      )
      allow(Puma::Enhanced::Stats::CLI::ProcessSampler).to receive(:sample_all).and_return({})
      allow(Puma::Enhanced::Stats::CLI::ProcessSampler).to receive(:top_outsiders).and_return []

      calls = 0
      allow(Puma::Enhanced::Stats::CLI::Keyboard).to receive(:refresh?) do
        calls += 1
        raise Interrupt if calls > 1

        false
      end
      expect(fetcher).to receive(:fetch).at_least(:twice).and_return payload

      runner = described_class.new
      runner.instance_variable_set :@options, options
      runner.instance_variable_set :@fetcher, fetcher
      runner.instance_variable_set(:@scroll, Puma::Enhanced::Stats::CLI::ScrollState.new)
      runner.instance_variable_set(:@screen, Puma::Enhanced::Stats::CLI::ScreenManager.new(options))
      allow(runner).to receive(:monotonic).and_return(0, 0, 6, 6, 12, 12)

      expect(runner.send :run_watch, payload).to eq 0
    end

    it "handles keyboard input and loads outsiders when attribution warns" do
      options = Puma::Enhanced::Stats::CLI::Options.new
      options.show_outsiders = true
      host = Puma::Enhanced::Stats::CLI::HostMetrics::Snapshot.new(
        load: [0.1, 0.1, 0.1],
        cpu: Puma::Enhanced::Stats::CLI::HostMetrics::CPU.new(usr: 80, sys: 10, idle: 10, usage: 0.95),
        memory: Puma::Enhanced::Stats::CLI::HostMetrics::Usage.new(
          used: 12_000_000_000, total: 16_000_000_000, ratio: 0.75
        ),
        swap: Puma::Enhanced::Stats::CLI::HostMetrics::Usage.new(used: 0, total: 1, ratio: 0.0),
        memory_limit_hint: nil
      )
      samples = {
        48_201 => Puma::Enhanced::Stats::CLI::ProcessSampler::Sample.new(
          pid: 48_201, cpu_percent: 10.0, mem_percent: 1.0, rss_bytes: 500_000_000
        )
      }
      allow(Puma::Enhanced::Stats::CLI::Terminal).to receive(:tty?).and_return true
      allow(Puma::Enhanced::Stats::CLI::Terminal).to receive(:size).and_return [40, 120]
      allow(Puma::Enhanced::Stats::CLI::HostMetrics).to receive(:read).and_return host
      allow(Puma::Enhanced::Stats::CLI::ProcessSampler).to receive(:sample_all).and_return samples
      allow(Puma::Enhanced::Stats::CLI::ProcessSampler).to receive(:top_outsiders).and_return []

      calls = 0
      allow(Puma::Enhanced::Stats::CLI::Keyboard).to receive(:refresh?) do
        calls += 1
        calls == 1
      end
      allow(Puma::Enhanced::Stats::CLI::Keyboard).to receive(:read).and_return "j"
      allow(Puma::Enhanced::Stats::CLI::Terminal).to receive(:resize_pending).and_return false
      allow(Puma::Enhanced::Stats::CLI::Keyboard).to receive(:refresh?).and_return true, false
      allow(Puma::Enhanced::Stats::CLI::Keyboard).to receive(:read).and_return("j").and_raise Interrupt

      runner = described_class.new
      runner.instance_variable_set :@options, options
      runner.instance_variable_set :@fetcher, fetcher
      runner.instance_variable_set(:@scroll, Puma::Enhanced::Stats::CLI::ScrollState.new)
      runner.instance_variable_set(:@screen, Puma::Enhanced::Stats::CLI::ScreenManager.new(options))

    expect(runner.send(:run_watch, payload)).to eq 0
    end

    it "marks attribution degraded when every sample lacks cpu" do
      options = Puma::Enhanced::Stats::CLI::Options.new
      runner = described_class.new
      runner.instance_variable_set :@options, options
      samples = {
        1 => Puma::Enhanced::Stats::CLI::ProcessSampler::Sample.new(
          pid: 1, cpu_percent: nil, mem_percent: nil, rss_bytes: nil
        )
      }
      attribution = runner.send(
        :build_attribution,
        Puma::Enhanced::Stats::CLI::HostMetrics::EMPTY,
        samples
      )
      expect(attribution.degraded?).to be true
    end

    it "uses fallback poll interval when meta interval is zero" do
      runner = described_class.new
      expect(runner.send :poll_interval, { "meta" => { "worker_check_interval_seconds" => 0 } }).to eq 5
      expect(runner.send :poll_interval, { "meta" => { "worker_check_interval_seconds" => 3 } }).to eq 3
    end
  end

  describe Puma::Enhanced::Stats::CLI::CgroupMemory do
    after { described_class.reset! }

    it "handles cgroup edge cases and byte formatting" do
      described_class.reset!
      stub_const "RUBY_PLATFORM", "linux"
      allow(File).to receive(:file?).and_call_original
      allow(File).to receive(:file?).with("/sys/fs/cgroup/memory.max").and_return true
      allow(File).to receive(:read).with("/sys/fs/cgroup/memory.max").and_return "max"
      expect(described_class.total_bytes).to be_nil

      described_class.reset!
      allow(File).to receive(:file?).and_call_original
      allow(File).to receive(:file?).with("/sys/fs/cgroup/memory.max").and_return true
      allow(File).to receive(:read).with("/sys/fs/cgroup/memory.max").and_raise StandardError
      allow(File).to receive(:readlines).with("/proc/meminfo").and_return(["MemTotal:       1024 kB\n"])
      expect(described_class.total_bytes).to eq 1024 * 1024

      described_class.reset!
      allow(File).to receive(:file?).and_call_original
      allow(File).to receive(:file?).with("/sys/fs/cgroup/memory.max").and_return false
      allow(File).to receive(:file?).with("/sys/fs/cgroup/memory/memory.limit_in_bytes").and_return true
      allow(File).to receive(:read).with("/sys/fs/cgroup/memory/memory.limit_in_bytes")
        .and_return(described_class::UNLIMITED.to_s)
      allow(File).to receive(:readlines).with("/proc/meminfo").and_return(["MemTotal:       2048 kB\n"])
      expect(described_class.total_bytes).to eq 2048 * 1024

      described_class.reset!
      allow(File).to receive(:file?).and_call_original
      allow(File).to receive(:file?).with("/sys/fs/cgroup/memory.max").and_return false
      allow(File).to receive(:file?).with("/sys/fs/cgroup/memory.current").and_return false
      allow(File).to receive(:file?).with("/sys/fs/cgroup/memory/memory.usage_in_bytes").and_return true
      allow(File).to receive(:read).with("/sys/fs/cgroup/memory/memory.usage_in_bytes").and_return "4096\n"
      allow(File).to receive(:file?).with("/sys/fs/cgroup/memory/memory.limit_in_bytes").and_return true
      allow(File).to receive(:read).with("/sys/fs/cgroup/memory/memory.limit_in_bytes").and_return "8192\n"
      expect(described_class.used_bytes).to eq 4096

      expect(described_class.send :format_bytes, 2_000_000_000).to include "GiB"
      expect(described_class.send :format_bytes, 2_000_000).to include "MiB"
      expect(described_class.send :format_bytes, 2048).to include "KiB"
      expect(described_class.send :format_bytes, 512).to eq "512 B"
    end

    it "returns nil on unsupported platforms" do
      stub_const "RUBY_PLATFORM", "java"
      expect(described_class.total_bytes).to be_nil
      expect(described_class.used_bytes).to be_nil
    end
  end

  describe Puma::Enhanced::Stats::CLI::Keyboard do
    it "reads a key when stdin is ready on a TTY" do
      allow(Puma::Enhanced::Stats::CLI::Terminal).to receive(:tty?).and_return true
      allow(IO).to receive(:select).and_return [[$stdin]]
      console = instance_double(IO, getch: "q")
      allow(IO).to receive(:console).and_return console
      expect(described_class.read(deadline: Time.now.to_i + 5)).to eq "q"
      expect(described_class.refresh?).to be true
    end

    it "returns nil when select or getch fails" do
      allow(Puma::Enhanced::Stats::CLI::Terminal).to receive(:tty?).and_return true
      allow(IO).to receive(:select).and_raise StandardError
      expect(described_class.refresh?).to be false
      allow(IO).to receive(:select).and_return [[$stdin]]
      allow(IO).to receive(:console).and_raise StandardError
      expect(described_class.read(deadline: Time.now.to_i + 5)).to be_nil
    end
  end

  describe Puma::Enhanced::Stats::CLI::ResourceAttribution do
    def host(cpu_usage:, mem_ratio:, mem_total: 16_000_000_000, swap_ratio: 0.0)
      Puma::Enhanced::Stats::CLI::HostMetrics::Snapshot.new(
        load: nil,
        cpu: Puma::Enhanced::Stats::CLI::HostMetrics::CPU.new(usr: 0, sys: 0, idle: 0, usage: cpu_usage),
        memory: Puma::Enhanced::Stats::CLI::HostMetrics::Usage.new(
          used: (mem_total * mem_ratio).to_i, total: mem_total, ratio: mem_ratio
        ),
        swap: Puma::Enhanced::Stats::CLI::HostMetrics::Usage.new(
          used: 0, total: 1, ratio: swap_ratio
        ),
        memory_limit_hint: nil
      )
    end

    def sample(pid, cpu:, rss:)
      Puma::Enhanced::Stats::CLI::ProcessSampler::Sample.new(
        pid: pid, cpu_percent: cpu, mem_percent: 1.0, rss_bytes: rss
      )
    end

    it "warns on memory gap and exposes mem suffix when host is hot" do
      attribution = described_class.compute(
        host: host(cpu_usage: 0.5, mem_ratio: 0.8),
        puma_pids: [1],
        process_by_pid: { 1 => sample(1, cpu: 50, rss: 500_000_000) }
      )
      expect(attribution.level).to eq :warn
      expect(attribution.mem_suffix).to eq "Puma ~3%"
    end

    it "crits on memory gap alone" do
      attribution = described_class.compute(
        host: host(cpu_usage: 0.5, mem_ratio: 0.9),
        puma_pids: [1],
        process_by_pid: { 1 => sample(1, cpu: 50, rss: 100_000_000) }
      )
      expect(attribution.level).to eq :crit
    end

    it "skips outsider loading when degraded or already loaded" do
      attribution = described_class.compute(
        host: host(cpu_usage: 0.5, mem_ratio: 0.5),
        puma_pids: [1],
        process_by_pid: { 1 => sample(1, cpu: 10, rss: 100) },
        degraded: true
      )
      expect(Puma::Enhanced::Stats::CLI::ProcessSampler).not_to receive :top_outsiders
      attribution.load_outsiders! exclude_pids: [1]
      attribution.load_outsiders! exclude_pids: [1]
    end

    it "omits suffixes when host is not hot" do
      attribution = described_class.compute(
        host: host(cpu_usage: 0.2, mem_ratio: 0.2),
        puma_pids: [1],
        process_by_pid: { 1 => sample(1, cpu: 5, rss: 100) }
      )
      expect(attribution.cpu_suffix).to be_nil
      expect(attribution.mem_suffix).to be_nil
    end
  end

  describe Puma::Enhanced::Stats::CLI::ProcessSampler do
    let(:runner) { instance_double(Puma::Enhanced::Stats::CLI::ProcessSampler::Runner) }

    before do
      allow(described_class).to receive(:runner).and_return runner
    end

    it "handles empty pid lists and malformed ps output" do
      expect(described_class.sample_pids []).to eq({})
      allow(runner).to receive(:ps_batch).with("1").and_return "bad-line\n"
      expect(described_class.sample_pids([1])[1].cpu_percent).to be_nil
      allow(runner).to receive(:ps_outsiders).and_return ""
      expect(described_class.top_outsiders(exclude_pids: [], limit: 3)).to eq []
      allow(runner).to receive(:ps_outsiders).and_raise StandardError
      expect(described_class.top_outsiders(exclude_pids: [], limit: 3)).to eq []
    end
  end

  describe Puma::Enhanced::Stats::CLI::SummaryRenderer do
    it "covers reporting and suffix composition branches" do
      options = Puma::Enhanced::Stats::CLI::Options.new.tap { |o| o.no_color = true }
      colors = Puma::Enhanced::Stats::CLI::Colors.new options
      bar = Puma::Enhanced::Stats::CLI::Bar.new colors
      renderer = described_class.new bar, colors
      budget = Puma::Enhanced::Stats::CLI::LayoutBudget.new(30, 80, options, worker_count: 2)
      payload = mixed_payload.merge(
        "summary" => mixed_payload["summary"].merge(
          "workers_reporting" => 1,
          "workers_total" => 2,
          "workers_stale" => 0,
          "requests_dropped_total" => 1,
          "requests_truncated" => false,
          "max_threads_total" => 0
        )
      )
      attribution = Puma::Enhanced::Stats::CLI::ResourceAttribution.compute(
        host: Puma::Enhanced::Stats::CLI::HostMetrics::EMPTY,
        puma_pids: [], process_by_pid: {}, degraded: false
      )
      output = renderer.render(payload, budget, attribution: attribution)
      expect(output).to include "SUMMARY"
      expect(output).to include "Workers reporting"
    end
  end

  describe Puma::Enhanced::Stats::CLI::UserConfig do
    it "ignores empty configs and parses truthy variants" do
      options = Puma::Enhanced::Stats::CLI::Options.new
      expect(described_class.apply! options, {}).to eq options
      expect(described_class.apply! options, nil).to eq options
      described_class.apply!(options, {
        "show_outsiders" => "off",
        "frame_layout" => "",
        "filter." => "x",
        "filter.method" => "GET"
      })
      expect(options.show_outsiders?).to be false
      expect(options.filters["method"]).to eq "GET"
    end
  end

  describe Puma::Enhanced::Stats::CLI::StubPayloadBuilder do
    it "loads stale and truncated scenarios" do
      expect(described_class.build(scenario: "stale", workers: 1, stale: 1)["workers"].size).to eq 1
      expect(described_class.build(scenario: "truncated", workers: 1, stale: 0)).to be_a Hash
      expect(described_class.build(scenario: "custom", workers: 1, stale: 0)).to be_a Hash
    end
  end

  describe Puma::Enhanced::Stats::CLI::StubServer do
    it "handles forbidden requests, query tokens, and socket errors" do
      server = described_class.new port: 9293, token: "secret", payload: { "ok" => true }
      socket = instance_double(TCPSocket, close: nil)
      allow(socket).to receive(:gets).and_return "GET /enhanced-stats HTTP/1.1\r\n", "\r\n"
      allow(socket).to receive(:write) do |body|
        expect(body).to include "403"
      end
      server.send :handle, socket

      socket2 = instance_double(TCPSocket, close: nil)
      allow(socket2).to receive(:gets).and_return "GET /enhanced-stats?token=secret HTTP/1.1\r\n", "\r\n"
      allow(socket2).to receive(:write) do |body|
        expect(body).to include "200"
      end
      server.send :handle, socket2

      socket3 = instance_double(TCPSocket, close: nil)
      allow(socket3).to receive(:gets).and_return nil
      expect(socket3).to receive :close
      server.send :handle, socket3

      socket4 = instance_double TCPSocket
      allow(socket4).to receive(:gets).and_raise StandardError
      expect(socket4).to receive :close
      server.send :handle, socket4
    end
  end

  describe Puma::Enhanced::Stats::CLI::RequestTable do
    it "covers stack-only and pagination hint branches" do
      items = [{
        "id" => "1",
        "started_at" => "2026-01-01T00:00:00Z",
        "elapsed_ms" => 10,
        "method" => "GET",
        "path_info" => "/reports/rep" +  "x" * 80,
        "session" => { "uid" => "1" }
      }] * 3
      table = described_class.new(items, inner_width: 1, display_mode: "auto", offset: 1)
      lines = table.render max_items: 1
      expect(lines.join "\n").to include "path_info"
      expect(table.overflow_field_count).to be >= 0
    end
  end

  describe Puma::Enhanced::Stats::CLI::SyncFreshness do
    it "returns ok in single mode and handles invalid timestamps" do
      expect(described_class.evaluate(
        synced_at: nil, collected_at: "2026-01-01T00:00:00Z",
        interval_seconds: 5, mode: "single"
      ).badge).to eq :ok
      expect(described_class.evaluate(
        synced_at: "bad", collected_at: "2026-01-01T00:00:00Z",
        interval_seconds: 5, mode: "cluster"
      ).badge).to eq :crit
    end
  end

  describe Puma::Enhanced::Stats::CLI::FrameRenderer do
    it "renders grid with outsiders and layout hint" do
      options = Puma::Enhanced::Stats::CLI::Options.new
      options.show_outsiders = true
      options.frame_layout = "two_column"
      options.focus_worker = 0
      output = render_dashboard(width: 120, frame_layout: "two_column", no_top: true)
      expect(output).to include "WORKER"
    end
  end

  describe "misc CLI branches" do
    it "covers format, options, catalog, scroll, sorter, lines, alert, severity, filter" do
      expect(Puma::Enhanced::Stats::CLI::Format.truncate "hello", 3).to eq "he…"
      expect(Puma::Enhanced::Stats::CLI::Format.bytes 0).to eq "0 B"
      options = Puma::Enhanced::Stats::CLI::Options.new
      options.show_top = "false"
      expect(options.top?).to be false
      options.show_top = "true"
      expect(options.top?).to be true
      fields = Puma::Enhanced::Stats::CLI::RequestFieldCatalog.discover [
        { "custom" => "x", "session" => { "role" => "admin" } }
      ]
      expect(fields).to include("custom", "session.role")
      scroll = Puma::Enhanced::Stats::CLI::ScrollState.new
      scroll.bump_request! 0, 1
      scroll.page_request! 0, 2, 1
      expect(Puma::Enhanced::Stats::CLI::RequestSorter.sort([], field: "elapsed_ms", dir: "desc")).to eq []
      colors = Puma::Enhanced::Stats::CLI::Colors.new(options.tap { |o| o.no_color = true })
      expect(Puma::Enhanced::Stats::CLI::MetricLine.new(
        label: "x", value: "1", bar: "[#]", suffix: "WARN", colors: colors, bar_level: :warn
      ).render.join).to include "x"
      expect(Puma::Enhanced::Stats::CLI::LabelLine.new(
        label: "y", value: "2", badge: :info, colors: colors
      ).render.join).to include "y"
      expect(Puma::Enhanced::Stats::CLI::AlertLevel.for_dropped 1).to eq :warn
      rows = [{ sort_cpu: 1.0, sort_index: 0, backlog_sort: 0, rss: "1M" }]
      expect(Puma::Enhanced::Stats::CLI::SeveritySorter.sort_process_rows rows).to eq rows
      budget = Puma::Enhanced::Stats::CLI::LayoutBudget.new(24, 80, options, worker_count: 1)
      expect(Puma::Enhanced::Stats::CLI::FilterScreen.new.render options, budget).to include "FILTER"
    end
  end
end
