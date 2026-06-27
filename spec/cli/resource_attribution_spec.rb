# frozen_string_literal: true

require "puma/enhanced/stats/cli/host_metrics"
require "puma/enhanced/stats/cli/process_sampler"
require "puma/enhanced/stats/cli/resource_attribution"

RSpec.describe Puma::Enhanced::Stats::CLI::ResourceAttribution do
  def host_snapshot(cpu_usage:, mem_ratio: 0.2, swap_ratio: 0.0, mem_total: 16_000_000_000)
    Puma::Enhanced::Stats::CLI::HostMetrics::Snapshot.new(
      load: [0.1, 0.1, 0.1],
      cpu: Puma::Enhanced::Stats::CLI::HostMetrics::CPU.new(
        usr: 80, sys: 10, idle: 10, usage: cpu_usage
      ),
      memory: Puma::Enhanced::Stats::CLI::HostMetrics::Usage.new(
        used: (mem_total * mem_ratio).to_i,
        total: mem_total,
        ratio: mem_ratio
      ),
      swap: Puma::Enhanced::Stats::CLI::HostMetrics::Usage.new(
        used: (2_000_000_000 * swap_ratio).to_i,
        total: 2_000_000_000,
        ratio: swap_ratio
      ),
      memory_limit_hint: nil
    )
  end

  def sample(pid, cpu:, rss:)
    Puma::Enhanced::Stats::CLI::ProcessSampler::Sample.new(
      pid: pid,
      cpu_percent: cpu,
      mem_percent: 1.0,
      rss_bytes: rss
    )
  end

  it "returns degraded attribution when requested" do
    attribution = described_class.compute(
      host: host_snapshot(cpu_usage: 0.9),
      puma_pids: [1],
      process_by_pid: { 1 => sample(1, cpu: 5, rss: 100) },
      degraded: true
    )

    expect(attribution.degraded?).to be true
    expect(attribution.warn_or_crit?).to be false
    expect(attribution.cpu_suffix).to be_nil
  end

  it "reports ok when host pressure matches puma usage" do
    attribution = described_class.compute(
      host: host_snapshot(cpu_usage: 0.5, mem_ratio: 0.5),
      puma_pids: [1, 2],
      process_by_pid: {
        1 => sample(1, cpu: 25, rss: 4_000_000_000),
        2 => sample(2, cpu: 20, rss: 4_000_000_000)
      }
    )

    expect(attribution.level).to eq :ok
    expect(attribution.cpu_suffix).to be_nil
    expect(attribution.show_summary_line?).to be false
  end

  it "warns when host cpu is high but puma cpu is low" do
    attribution = described_class.compute(
      host: host_snapshot(cpu_usage: 0.91, mem_ratio: 0.7),
      puma_pids: [1],
      process_by_pid: { 1 => sample(1, cpu: 14, rss: 1_000_000_000) }
    )

    expect(attribution.level).to eq :warn
    expect(attribution.cpu_gap).to be >= 30
    expect(attribution.cpu_suffix).to eq "Puma ~14%"
    expect(attribution.summary_value).to match /CPU91\/M\d+/
    expect(attribution.show_summary_line?).to be true
  end

  it "crits when cpu gap is very large or swap is hot" do
    attribution = described_class.compute(
      host: host_snapshot(cpu_usage: 0.95, mem_ratio: 0.8),
      puma_pids: [1],
      process_by_pid: { 1 => sample(1, cpu: 10, rss: 500_000_000) }
    )

    expect(attribution.level).to eq :crit

    swap_crit = described_class.compute(
      host: host_snapshot(cpu_usage: 0.5, mem_ratio: 0.5, swap_ratio: 0.6),
      puma_pids: [1],
      process_by_pid: { 1 => sample(1, cpu: 40, rss: 4_000_000_000) }
    )
    expect(swap_crit.level).to eq :crit
  end

  it "loads outsiders lazily" do
    attribution = described_class.compute(
      host: host_snapshot(cpu_usage: 0.91, mem_ratio: 0.7),
      puma_pids: [1],
      process_by_pid: { 1 => sample(1, cpu: 14, rss: 1_000_000_000) }
    )
    allow(Puma::Enhanced::Stats::CLI::ProcessSampler).to receive(:top_outsiders)
      .with(exclude_pids: [1], limit: 3)
      .and_return([
        Puma::Enhanced::Stats::CLI::ProcessSampler::Outsider.new(
          pid: 9912, cpu_percent: 72.4, mem_percent: 2.8, rss_bytes: 210_000_000, command: "sidekiq"
        )
      ])

    attribution.load_outsiders! exclude_pids: [1]

    expect(attribution.outsiders.first.command).to eq "sidekiq"
    expect(Puma::Enhanced::Stats::CLI::ProcessSampler).to have_received(:top_outsiders).once
  end
end
