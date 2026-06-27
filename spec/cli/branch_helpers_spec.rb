# frozen_string_literal: true

require "puma/enhanced/stats/cli/keyboard"
require "puma/enhanced/stats/cli/alert_level"
require "puma/enhanced/stats/cli/request_field_catalog"
require "puma/enhanced/stats/cli/screen_manager"

RSpec.describe Puma::Enhanced::Stats::CLI::Keyboard do
  it "returns nil when stdin is not ready" do
    allow(Puma::Enhanced::Stats::CLI::Terminal).to receive(:tty?).and_return true
    allow(Puma::Enhanced::Stats::CLI::Keyboard).to receive(:refresh?).and_return false

    expect(described_class.read(deadline: Time.now.to_i + 5)).to be_nil
  end
end

RSpec.describe Puma::Enhanced::Stats::CLI::AlertLevel do
  it "returns ok for non-truncated requests" do
    expect(described_class.for_truncated false).to eq :ok
  end
end

RSpec.describe Puma::Enhanced::Stats::CLI::RequestFieldCatalog do
  it "deduplicates discovered fields" do
    item = { "id" => "1", "started_at" => "t", "custom" => "x", "session" => { "uid" => "1" } }
    expect(described_class.discover [item, item]).to eq(
      %w[elapsed id method path_info remote_ip custom session.uid]
    )
  end
end

RSpec.describe Puma::Enhanced::Stats::CLI::ScreenManager do
  it "ignores help navigation when another modal is open" do
    options = Puma::Enhanced::Stats::CLI::Options.new
    options.modal = :sort
    options.help_tab = 0
    manager = described_class.new options

    manager.handle("n", scroll: Puma::Enhanced::Stats::CLI::ScrollState.new, payload: { "workers" => [] })

    expect(options.help_tab).to eq 0
  end
end
