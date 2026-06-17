# frozen_string_literal: true

require "puma"
require "puma/cluster/worker_handle"

RSpec.describe Puma::Enhanced::Stats::WorkerHandle do
  subject(:handle) { Puma::Cluster::WorkerHandle.new(0, 1234, 0, {}) }

  it "stores enhanced stats from worker ping payload" do
    status = '{"backlog":0,"running":1,"pool_capacity":5,"max_threads":5,"requests_count":0,' \
             '"enhanced_stats":{"items":[{"id":"a","method":"GET","path_info":"/"}],"dropped_count":0,"truncated":false,' \
             '"process":{"rss_bytes":1000,"cpu_percent":1.5}}}'
    handle.ping!(status)

    stats = handle.enhanced_stats
    expect(stats[:items].size).to eq(1)
    expect(stats[:process][:rss_bytes]).to eq(1000)
    expect(stats[:dropped_count]).to eq(0)
  end

  it "delegates to super when ping json is invalid" do
    expect { handle.ping!(" \"broken\" }") }.not_to raise_error
    expect(handle.enhanced_stats[:items]).to be_empty
  end

  it "delegates to super when ping has no json payload" do
    expect { handle.ping!("") }.not_to raise_error
    expect(handle.enhanced_stats[:items]).to be_empty
  end

  it "tracks worker max keys across pings" do
    skip "WORKER_MAX_KEYS unavailable before Puma 7" unless Puma::Cluster::WorkerHandle.const_defined?(:WORKER_MAX_KEYS)

    handle.ping!(" \"backlog_max\":2, \"reactor_max\":1, \"running\":1, \"pool_capacity\":5, \"max_threads\":5, \"requests_count\":0 }")
    handle.ping!(" \"backlog_max\":8, \"reactor_max\":3, \"running\":1, \"pool_capacity\":5, \"max_threads\":5, \"requests_count\":0 }")

    expect(handle.last_status[:backlog_max]).to eq(8)

    handle.ping!(" \"backlog_max\":1, \"reactor_max\":1, \"running\":1, \"pool_capacity\":5, \"max_threads\":5, \"requests_count\":0 }")

    expect(handle.last_status[:backlog_max]).to eq(8)
  end

  it "leaves enhanced stats empty when ping has no enhanced_stats payload" do
    handle.ping!('{"backlog":0,"running":1,"pool_capacity":5,"max_threads":5,"requests_count":0}')

    expect(handle.enhanced_stats[:items]).to be_empty
    expect(handle.enhanced_stats[:synced_at]).to be_nil
  end

  it "applies puma status without worker max tracking when keys are unavailable" do
    allow(handle.class).to receive(:const_defined?).and_call_original
    allow(handle.class).to receive(:const_defined?).with(:WORKER_MAX_KEYS).and_return(false)

    handle.ping!(" \"backlog\":2, \"running\":1, \"pool_capacity\":5, \"max_threads\":5, \"requests_count\":0 }")

    expect(handle.last_status[:backlog]).to eq(2)
  end
end
