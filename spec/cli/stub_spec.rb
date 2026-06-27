# frozen_string_literal: true

require "puma/enhanced/stats/cli/stub_payload_builder"
require "puma/enhanced/stats/cli/stub_server"

RSpec.describe Puma::Enhanced::Stats::CLI::StubPayloadBuilder do
  it "loads mixed scenario fixture" do
    payload = described_class.build scenario: "mixed", workers: 2, stale: 1
    expect(payload["workers"].size).to eq 2
    expect(payload["summary"]["workers_stale"]).to eq 1
    expect(payload["meta"]["gem_version"]).to eq(Puma::Enhanced::Stats::VERSION)
  end
end

RSpec.describe Puma::Enhanced::Stats::CLI::StubServer do
  it "builds a WEBrick server for enhanced-stats" do
    payload = { "schema_version" => 1 }
    server = described_class.new payload: payload
    expect(server).to be_a described_class
  end

  it "closes the listener when interrupted" do
    listener = instance_double(TCPServer, addr: [nil, nil, nil, nil, 9293], close: nil)
    allow(listener).to receive(:closed?).and_return false
    allow(listener).to receive(:accept).and_raise Interrupt
    allow(TCPServer).to receive(:new).and_return listener

    expect { described_class.new(payload: {}).start }.not_to raise_error
    expect(listener).to have_received :close
  end
end
