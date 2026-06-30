# frozen_string_literal: true

require "puma/launcher"

RSpec.describe Puma::Enhanced::Stats::Launcher do
  describe "#enhanced_stats" do
    it "delegates to the cluster runner" do
      launcher = Puma::Launcher.new(Puma::Configuration.new { |user| user.workers 1 })
      cluster = launcher.instance_variable_get(:@runner)
      payload = { collected_at: Time.now.utc.iso8601, worker_status: [] }
      allow(cluster).to receive(:enhanced_stats).and_return(payload)

      expect(launcher.enhanced_stats).to equal(payload)
    end

    it "delegates to the single runner" do
      launcher = Puma::Launcher.new(Puma::Configuration.new)
      single = launcher.instance_variable_get(:@runner)
      payload = { collected_at: Time.now.utc.iso8601, worker_status: [] }
      allow(single).to receive(:enhanced_stats).and_return(payload)

      expect(launcher.enhanced_stats).to equal(payload)
    end
  end
end
