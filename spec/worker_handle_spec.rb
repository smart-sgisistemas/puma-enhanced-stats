# frozen_string_literal: true

require "puma/cluster"

RSpec.describe Puma::Enhanced::Stats::WorkerHandle do
  let(:options) { Puma::Launcher.new(Puma::Configuration.new).config.options }

  def worker_handle(index:, pid:)
    Puma::Cluster::WorkerHandle.new(index, pid, 0, options)
  end

  it "exposes last_enhanced_status like last_status" do
    handle = worker_handle(index: 0, pid: 123)

    expect(handle.last_enhanced_checkin).to be_nil
    expect(handle.last_enhanced_status).to eq(empty_enhanced_status)
  end

  it "stores snapshot via enhanced_ping!" do
    handle = worker_handle(index: 0, pid: 123)
    frozen = Time.utc(2026, 1, 1, 12, 0, 0)

    allow(Time).to receive(:now).and_return(frozen)
    handle.enhanced_ping!(
      wire_row(
        index: 0,
        pid: 123,
        items: [{ id: "req" }],
        backlog: 2,
        running: 1
      )
    )

    expect(handle.last_enhanced_checkin).to eq(frozen)
    expect(handle.last_enhanced_status[:requests].first[:id]).to eq("req")
    expect(handle.last_enhanced_status[:stats][:backlog]).to eq(2)
    expect(handle.last_enhanced_status[:stats][:running]).to eq(1)
  end

  it "starts empty on a new handle after worker replacement" do
    handle = worker_handle(index: 0, pid: 123)
    handle.enhanced_ping!(
      wire_row(
        index: 0,
        pid: 123,
        items: [{ id: "stale" }],
        backlog: 1
      )
    )

    replacement = worker_handle(index: 0, pid: 456)

    expect(replacement.last_enhanced_status[:requests]).to be_empty
    expect(replacement.last_enhanced_checkin).to be_nil
  end
end
