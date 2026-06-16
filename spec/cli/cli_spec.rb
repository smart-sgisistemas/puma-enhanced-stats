# frozen_string_literal: true

require "puma/enhanced/stats/cli"

RSpec.describe Puma::Enhanced::Stats::CLI do
  it "loads the CLI module" do
    expect(described_class).to be_a(Module)
    expect(Puma::Enhanced::Stats::CLI::Runner).to be_a(Class)
  end
end
