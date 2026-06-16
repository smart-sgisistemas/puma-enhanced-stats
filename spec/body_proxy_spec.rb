# frozen_string_literal: true

RSpec.describe Puma::Enhanced::Stats::BodyProxy do
  it "calls callback once after each" do
    calls = 0
    proxy = described_class.new(["chunk"]) { calls += 1 }

    proxy.each { |_chunk| }
    proxy.each { |_chunk| }

    expect(calls).to eq(1)
  end

  it "returns an enumerator from each without a block" do
    proxy = described_class.new(%w[a]) {}

    expect(proxy.each).to be_a(Enumerator)
  end

  it "closes bodies that do not implement close" do
    calls = 0
    proxy = described_class.new(Object.new) { calls += 1 }

    expect { proxy.close }.not_to raise_error
    expect(calls).to eq(1)
  end

  it "reports delegated methods via respond_to_missing?" do
    body = Object.new
    def body.custom = "ok"
    proxy = described_class.new(body) {}

    expect(proxy.respond_to?(:custom)).to be(true)
  end

  it "calls callback on close" do
    calls = 0
    body = Object.new
    def body.close; end
    proxy = described_class.new(body) { calls += 1 }

    proxy.close

    expect(calls).to eq(1)
  end

  it "delegates other methods to the wrapped body" do
    body = ["a", "b"]
    proxy = described_class.new(body) {}

    expect(proxy.to_a).to eq(%w[a b])
  end

  it "returns false from respond_to_missing? when the body does not implement the method" do
    proxy = described_class.new(Object.new) {}

    expect(proxy.respond_to?(:not_a_real_method)).to be(false)
  end

  it "forwards arbitrary methods via method_missing" do
    body = Object.new
    def body.custom = "ok"
    proxy = described_class.new(body) {}

    expect(proxy.custom).to eq("ok")
  end

  it "returns an enumerator from method_missing each without a block" do
    proxy = described_class.new(%w[a]) {}

    expect(proxy.send(:method_missing, :each)).to be_a(Enumerator)
  end

  it "streams via method_missing each when a block is given" do
    proxy = described_class.new(%w[a]) {}
    chunks = []

    proxy.send(:method_missing, :each) { |chunk| chunks << chunk }

    expect(chunks).to eq(%w[a])
  end
end
