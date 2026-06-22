# frozen_string_literal: true

require "puma/cluster"

RSpec.describe Puma::Enhanced::Stats::WorkerHandle do
  let(:options) { Puma::Launcher.new(Puma::Configuration.new).config.options }

  def worker_handle(index:, pid:)
    Puma::Cluster::WorkerHandle.new(index, pid, 0, options)
  end

  it "exposes last_enhanced_stats like last_status" do
    handle = worker_handle(index: 0, pid: 123)

    expect(handle.last_enhanced_stats).to eq(
      Puma::Enhanced::Stats::WorkerHandle::EMPTY_ENHANCED_STATS.dup
    )
  end

  it "stores snapshot via enhanced_ping!" do
    handle = worker_handle(index: 0, pid: 123)
    frozen = Time.utc(2026, 1, 1, 12, 0, 0)

    allow(Time).to receive(:now).and_return(frozen)
    handle.enhanced_ping!(
      items: [{ id: "req" }],
      dropped_count: 1,
      truncated: true,
      backlog: 2,
      running: 1
    )

    expect(handle.last_enhanced_stats[:items].first[:id]).to eq("req")
    expect(handle.last_enhanced_stats[:dropped_count]).to eq(1)
    expect(handle.last_enhanced_stats[:truncated]).to be(true)
    expect(handle.last_enhanced_stats[:backlog]).to eq(2)
    expect(handle.last_enhanced_stats[:running]).to eq(1)
    expect(handle.last_enhanced_stats[:synced_at]).to eq(frozen.iso8601)
  end

  it "starts empty on a new handle after worker replacement" do
    handle = worker_handle(index: 0, pid: 123)
    handle.enhanced_ping!(
      items: [{ id: "stale" }],
      dropped_count: 0,
      truncated: false,
      backlog: 1
    )

    replacement = worker_handle(index: 0, pid: 456)

    expect(replacement.last_enhanced_stats[:items]).to be_empty
    expect(replacement.last_enhanced_stats[:synced_at]).to be_nil
  end
end
