# frozen_string_literal: true

require "puma/enhanced/stats/cli/top_renderer"

RSpec.describe Puma::Enhanced::Stats::CLI::TopRenderer do
  it "sorts process rows by severity by default" do
    options = Puma::Enhanced::Stats::CLI::Options.new
    options.sort_process = "severity"
    colors = Puma::Enhanced::Stats::CLI::Colors.new(options.tap { |o| o.no_color = true })
    bar = Puma::Enhanced::Stats::CLI::Bar.new colors
    attribution = Puma::Enhanced::Stats::CLI::ResourceAttribution.compute(
      host: Puma::Enhanced::Stats::CLI::HostMetrics::EMPTY,
      puma_pids: [], process_by_pid: {}
    )
    renderer = described_class.new(options, bar, host: Puma::Enhanced::Stats::CLI::HostMetrics::EMPTY, attribution: attribution)
    rows = [
      { pid: 1, cpu: "1", mem: "1", rss: "1K", run_cap: "1/5", backlog: 0, pool: 0, w: 0,
        sort_cpu: 1.0, sort_index: 0, backlog_sort: 0 },
      { pid: 2, cpu: "2", mem: "2", rss: "2K", run_cap: "2/5", backlog: 1, pool: 0, w: 1,
        sort_cpu: 2.0, sort_index: 1, backlog_sort: 1 }
    ]
    sorted = renderer.send :sort_rows, rows
    expect(sorted.first[:backlog_sort]).to eq 1
  end

  it "renders cpu on two lines with full detail names and per-core blocks" do
    options = Puma::Enhanced::Stats::CLI::Options.new
    colors = Puma::Enhanced::Stats::CLI::Colors.new(options.tap { |o| o.no_color = true })
    bar = Puma::Enhanced::Stats::CLI::Bar.new colors
    host = Puma::Enhanced::Stats::CLI::HostMetrics::Snapshot.new(
      load: [0.1, 0.1, 0.1],
      cpu: Puma::Enhanced::Stats::CLI::HostMetrics::CPU.new(
        usr: 37.7, sys: 0.0, idle: 61.1, usage: 0.39,
        cores: [
          Puma::Enhanced::Stats::CLI::HostMetrics::CoreCPU.new(
            index: 0, usr: 40.0, sys: 1.0, idle: 59.0, usage: 0.41
          )
        ]
      ),
      memory: nil, swap: nil, memory_limit_hint: nil
    )
    attribution = Puma::Enhanced::Stats::CLI::ResourceAttribution.compute(
      host: host, puma_pids: [], process_by_pid: {}
    )
    renderer = described_class.new(options, bar, host: host, attribution: attribution)
    budget = Puma::Enhanced::Stats::CLI::LayoutBudget.new(24, 80, options, worker_count: 1)
    output = renderer.render_top(budget)

    expect(output).to include("user 37.7%")
    expect(output).to include("sys  0.0%")
    expect(output).to include("idle 61.1%")
    expect(output).to include("CPU")
    expect(output).to include("core 0")
    expect(output).to include("[")
    expect(output.scan("user ").size).to be >= 2
  end

  it "shows cpu line when usage is zero" do
    options = Puma::Enhanced::Stats::CLI::Options.new
    colors = Puma::Enhanced::Stats::CLI::Colors.new(options.tap { |o| o.no_color = true })
    bar = Puma::Enhanced::Stats::CLI::Bar.new colors
    host = Puma::Enhanced::Stats::CLI::HostMetrics::Snapshot.new(
      load: [0.1, 0.1, 0.1],
      cpu: Puma::Enhanced::Stats::CLI::HostMetrics::CPU.new(usr: 0, sys: 0, idle: 100, usage: 0.0),
      memory: nil, swap: nil, memory_limit_hint: nil
    )
    attribution = Puma::Enhanced::Stats::CLI::ResourceAttribution.compute(
      host: host, puma_pids: [], process_by_pid: {}
    )
    renderer = described_class.new(options, bar, host: host, attribution: attribution)
    budget = Puma::Enhanced::Stats::CLI::LayoutBudget.new(24, 80, options, worker_count: 1)

    expect(renderer.render_top(budget)).to include "CPU"
  end
end
