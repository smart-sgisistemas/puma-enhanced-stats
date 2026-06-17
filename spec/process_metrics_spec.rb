# frozen_string_literal: true

RSpec.describe Puma::Enhanced::Stats::ProcessMetrics do
  let(:empty) { described_class::EMPTY }

  it "returns rss and cpu from ps on linux or darwin" do
    skip "ps metrics are linux/darwin only" unless RUBY_PLATFORM.match?(/linux|darwin/i)

    result = described_class.read

    expect(result[:rss_bytes]).to be_a(Integer)
    expect(result[:rss_bytes]).to be_positive
    expect(result[:cpu_percent]).to be_a(Numeric)
  end

  it "returns empty metrics on unsupported platforms" do
    stub_const("RUBY_PLATFORM", "x64-mingw32")

    expect(described_class.read).to eq(empty)
  end

  it "returns empty metrics when ps fails" do
    allow(described_class).to receive(:`).and_raise(StandardError)

    expect(described_class.read).to eq(empty)
  end

  it "returns empty metrics when ps output is blank" do
    stub_const("RUBY_PLATFORM", "linux")
    allow(described_class).to receive(:`).and_return("")

    expect(described_class.read).to eq(empty)
  end
end
