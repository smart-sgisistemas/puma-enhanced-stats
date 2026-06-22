# frozen_string_literal: true

require "puma/launcher"

RSpec.describe Puma::Enhanced::Stats::Launcher do
  describe "#runner" do
    it "exposes the puma runner" do
      launcher = Puma::Launcher.new(Puma::Configuration.new)

      expect(launcher.runner).to be launcher.instance_variable_get(:@runner)
    end
  end

  describe "#run" do
    it "assigns current_requests config before boot" do
      custom = Puma::Enhanced::Stats::Configuration.new.tap { |c| c.request_limit = 9 }
      launcher = Puma::Launcher.new(Puma::Configuration.new)
      launcher.config.options[:enhanced_stats] = custom

      allow(launcher).to receive(:setup_signals)
      allow(launcher).to receive(:set_process_title)
      allow(launcher.instance_variable_get(:@runner)).to receive(:run)

      launcher.run

      expect(Puma::Enhanced::Stats::CurrentRequests.send(:instance).instance_variable_get(:@config)).to equal(custom)
    end
  end

  describe "#enhanced_stats" do
    it "delegates to the cluster runner" do
      launcher = Puma::Launcher.new(Puma::Configuration.new { |user| user.workers 1 })
      cluster = launcher.instance_variable_get(:@runner)
      payload = { schema_version: 1, meta: {}, summary: {}, workers: [] }
      allow(cluster).to receive(:enhanced_stats).and_return(payload)

      expect(launcher.enhanced_stats).to equal(payload)
    end

    it "delegates to the single runner" do
      launcher = Puma::Launcher.new(Puma::Configuration.new)
      single = launcher.instance_variable_get(:@runner)
      payload = { schema_version: 1, meta: {}, summary: {}, workers: [] }
      allow(single).to receive(:enhanced_stats).and_return(payload)

      expect(launcher.enhanced_stats).to equal(payload)
    end
  end
end
