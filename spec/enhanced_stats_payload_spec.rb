# frozen_string_literal: true

require "puma/launcher"

RSpec.describe "enhanced stats payload" do
  it "returns the full payload from launcher.enhanced_stats in cluster mode" do
    launcher = Puma::Launcher.new(Puma::Configuration.new { |user| user.workers 1 })
    allow(launcher.instance_variable_get(:@runner)).to receive(:enhanced_stats).and_return(
      started_at: Time.now.utc.iso8601,
      workers: 1,
      phase: 0,
      booted_workers: 1,
      old_workers: 0,
      collected_at: Time.now.utc.iso8601,
      workers_total: 1,
      workers_reporting: 1,
      workers_stale: 0,
      requests_in_flight: 1,
      backlog_total: 0,
      busy_threads_total: 1,
      max_threads_total: 1,
      pool_capacity_total: 1,
      worker_status: [
        enhanced_worker_status_row(
          index: 0,
          pid: 123,
          last_enhanced_checkin: Time.now.utc.iso8601,
          items: [{ id: "a", session: {} }],
          running: 1
        )
      ],
      versions: {
        puma: Puma::Const::PUMA_VERSION,
        "puma-enhanced-stats": Puma::Enhanced::Stats::VERSION,
        ruby: { engine: RUBY_ENGINE, version: RUBY_VERSION, patchlevel: RUBY_PATCHLEVEL }
      }
    )

    payload = launcher.enhanced_stats

    expect(payload).not_to have_key(:schema_version)
    expect(payload[:requests_in_flight]).to eq(1)
    expect(payload[:worker_status].first[:requests].first[:id]).to eq("a")
  end
end
