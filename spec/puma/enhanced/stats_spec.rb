# frozen_string_literal: true

RSpec.describe Puma::Enhanced::Stats do
  it "has a version number" do
    expect(Puma::Enhanced::Stats::VERSION).not_to be nil
  end

  it "defines the Stats module" do
    expect(described_class).to be_a(Module)
  end
end
