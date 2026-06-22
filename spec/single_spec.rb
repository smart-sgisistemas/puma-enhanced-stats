# frozen_string_literal: true

RSpec.describe Puma::Enhanced::Stats::Single do
  let(:single_launcher) { Puma::Launcher.new(Puma::Configuration.new) }
  let(:single) { single_launcher.instance_variable_get(:@runner) }

  before { Puma::Enhanced::Stats::CurrentRequests.reset! }

  it "reads the live registry in enhanced_stats" do
    Puma::Enhanced::Stats::CurrentRequests.register(
      "REQUEST_METHOD" => "GET",
      "PATH_INFO" => "/live",
      "QUERY_STRING" => "",
      "REMOTE_ADDR" => "127.0.0.1",
      "action_dispatch.request_id" => "single-enhanced-stats"
    )

    payload = single.enhanced_stats

    expect(payload[:workers].size).to eq(1)
    expect(payload[:workers].first[:requests][:items].first[:path_info]).to end_with("/live")
    expect(payload[:summary][:workers_total]).to eq(1)
  end
end
