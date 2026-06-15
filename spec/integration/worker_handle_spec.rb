# frozen_string_literal: true

require "puma"
require "puma/cluster/worker_handle"

RSpec.describe Puma::Enhanced::Stats::WorkerHandle do
  subject(:handle) { Puma::Cluster::WorkerHandle.new(0, 1234, 0, {}) }

  it "stores enhanced stats from worker ping payload" do
    status = 'p1234{"backlog":0,"running":1,"pool_capacity":5,"max_threads":5,"requests_count":0,' \
             '"_enhanced_stats":{"items":[{"id":"a","method":"GET","path_info":"/"}],"dropped_count":0,"truncated":false,' \
             '"process":{"rss_bytes":1000,"cpu_percent":1.5}}}'
    handle.ping!(status)

    stats = handle.enhanced_stats
    expect(stats[:items].size).to eq(1)
    expect(stats[:process]["rss_bytes"]).to eq(1000)
    expect(stats[:dropped_count]).to eq(0)
  end

  it "delegates to super when ping json is invalid" do
    expect { handle.ping!('p1234{"broken"') }.not_to raise_error
    expect(handle.enhanced_stats[:items]).to be_empty
  end

  it "tracks worker max keys across pings" do
    handle.ping!('p1234{"backlog_max":2,"reactor_max":1,"running":1,"pool_capacity":5,"max_threads":5,"requests_count":0}')
    handle.ping!('p1234{"backlog_max":8,"reactor_max":3,"running":1,"pool_capacity":5,"max_threads":5,"requests_count":0}')

    expect(handle.last_status[:backlog_max]).to eq(8)

    handle.ping!('p1234{"backlog_max":1,"reactor_max":1,"running":1,"pool_capacity":5,"max_threads":5,"requests_count":0}')

    expect(handle.last_status[:backlog_max]).to eq(8)
  end

  it "leaves enhanced stats empty when ping has no _enhanced_stats payload" do
    handle.ping!('p1234{"backlog":0,"running":1,"pool_capacity":5,"max_threads":5,"requests_count":0}')

    expect(handle.enhanced_stats[:items]).to be_empty
    expect(handle.enhanced_stats[:synced_at]).to be_nil
  end
end
