# frozen_string_literal: true

require "puma/launcher"

RSpec.describe "enhanced stats payload" do
  def default_workers
    [
      {
        index: 0,
        pid: 123,
        synced_at: Time.now.utc.iso8601,
        puma: Puma::Server::STAT_METHODS.to_h { |key| [key, 0] }.merge(running: 1),
        requests: {
          meta: {
            count: 1,
            request_limit: 100,
            limit_policy: "keep_longest",
            truncated: false,
            dropped_count: 0
          },
          items: [{ id: "a", session: {} }]
        }
      }
    ]
  end

  it "returns the full payload from launcher.enhanced_stats in cluster mode" do
    launcher = Puma::Launcher.new(Puma::Configuration.new { |user| user.workers 1 })
    allow(launcher.instance_variable_get(:@runner)).to receive(:enhanced_stats).and_return(
      schema_version: 1,
      meta: { mode: "cluster" },
      summary: { requests_in_flight: 1 },
      workers: default_workers
    )

    payload = launcher.enhanced_stats

    expect(payload[:schema_version]).to eq(1)
    expect(payload[:meta][:mode]).to eq("cluster")
    expect(payload[:summary][:requests_in_flight]).to eq(1)
  end

  context "single mode" do
    let(:launcher) do
      Puma::Launcher.new(Puma::Configuration.new { |user| user.worker_check_interval 5 })
    end

    before do
      Puma::Enhanced::Stats::CurrentRequests.reset!
      Puma::Enhanced::Stats::CurrentRequests.register(
        "REQUEST_METHOD" => "GET",
        "PATH_INFO" => "/slow",
        "QUERY_STRING" => "",
        "REMOTE_ADDR" => "127.0.0.1",
        "action_dispatch.request_id" => "runner-slow-request"
      )
    end

    it "returns the full payload from the single runner" do
      payload = launcher.enhanced_stats

      expect(payload[:schema_version]).to eq(1)
      expect(payload[:meta][:mode]).to eq("single")
      expect(payload[:workers].first[:requests][:items].first[:path_info]).to end_with("/slow")
      expect(payload[:summary][:workers_total]).to eq(1)
    end
  end
end
