# frozen_string_literal: true

require "puma/enhanced/stats/cli/payload_view"

RSpec.describe Puma::Enhanced::Stats::CLI::PayloadView do
  let(:cluster_payload) do
    JSON.parse(File.read(File.expand_path("../fixtures/stub/mixed-cluster.json", __dir__)))
  end

  let(:single_payload) do
    JSON.parse(File.read(File.expand_path("../fixtures/stub/single-server.json", __dir__)))
  end

  it "normalizes cluster worker_status rows" do
    view = described_class.wrap(cluster_payload)
    worker = view.workers.first

    expect(view.cluster?).to be true
    expect(view.mode).to eq "cluster"
    expect(view.single?).to be false
    expect(worker["single"]).to be false
    expect(worker["synced_at"]).to eq "2026-06-12T14:31:59Z"
    expect(worker.dig("puma", "backlog")).to eq 0
    expect(worker.dig("requests", "items").size).to eq 2
    expect(view.running_total).to eq 8
  end

  it "normalizes single-mode payloads from flat pool counters" do
    view = described_class.wrap(single_payload, server_pid: 12_345)
    worker = view.workers.first

    expect(view.single?).to be true
    expect(view.mode).to eq "single"
    expect(view.cluster?).to be false
    expect(view.raw).not_to have_key("worker_status")
    expect(view.worker_check_interval_seconds).to eq 0
    expect(view.running_total).to eq 2
    expect(view.backlog_total).to eq 0
    expect(worker["single"]).to be true
    expect(worker["pid"]).to eq 12_345
    expect(worker.dig("puma", "running")).to eq 2
    expect(worker.dig("requests", "items").size).to eq 2
  end

  it "reads cluster aggregate counters from the root payload" do
    view = described_class.wrap(cluster_payload)

    expect(view.workers_total).to eq 3
    expect(view.requests_in_flight).to eq 3
    expect(view.backlog_total).to eq 3
    expect(view.gem_version).to eq "1.0.0"
  end
end
