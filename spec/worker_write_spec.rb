# frozen_string_literal: true

RSpec.describe Puma::Enhanced::Stats::WorkerWrite do
  let(:io) { StringIO.new }

  let(:ping_message) do
    "p1234 \"backlog\":0, \"running\":1, \"pool_capacity\":5, \"max_threads\":5, \"requests_count\":0 }\n"
  end

  before do
    Puma::Enhanced::Stats::CurrentRequests.instance.reset!
  end

  it "injects _enhanced_stats into ping messages with brace-delimited JSON" do
    message = "p1234 {\"backlog\":0, \"running\":1, \"pool_capacity\":5, \"max_threads\":5, \"requests_count\":0}\n"

    described_class.new(io) << message

    payload = JSON.parse(io.string[/\{.*\}/])
    expect(payload["backlog"]).to eq(0)
    expect(payload["_enhanced_stats"]).to include("items", "process")
  end

  it "injects _enhanced_stats into worker ping messages" do
    Puma::Enhanced::Stats::CurrentRequests.instance.register(
      "REQUEST_METHOD" => "GET",
      "PATH_INFO" => "/slow",
      "QUERY_STRING" => "",
      "REMOTE_ADDR" => "127.0.0.1"
    )

    described_class.new(io) << ping_message

    payload = JSON.parse(io.string[/\{.*\}/])
    expect(payload["backlog"]).to eq(0)
    expect(payload["_enhanced_stats"]["items"].size).to eq(1)
    expect(payload["_enhanced_stats"]["items"].first["path_info"]).to end_with("/slow")
    expect(payload["_enhanced_stats"]["process"]).to include("rss_bytes", "cpu_percent")
  end

  it "passes through non-ping messages unchanged" do
    described_class.new(io) << "E11234\t{}\n"

    expect(io.string).to eq("E11234\t{}\n")
  end

  it "falls back when ping json is invalid" do
    message = "p1234 \"not-json\" }\n"
    described_class.new(io) << message

    expect(io.string).to eq(message)
  end
end
