# frozen_string_literal: true

RSpec.describe Puma::Enhanced::Stats::WorkerWrite do
  let(:io) { StringIO.new }

  let(:ping_message) do
    "p1234 \"backlog\":0, \"running\":1, \"pool_capacity\":5, \"max_threads\":5, \"requests_count\":0 }\n"
  end

  before do
    Puma::Enhanced::Stats::CurrentRequests.reset!
  end

  def parse_ping_payload output
    prefix = output[/\Ap\d+/] || ""
    JSON.parse(output.delete_prefix(prefix), symbolize_names: true)
  end

  it "injects enhanced_stats into worker ping messages" do
    Puma::Enhanced::Stats::CurrentRequests.register(
      "REQUEST_METHOD" => "GET",
      "PATH_INFO" => "/slow",
      "QUERY_STRING" => "",
      "REMOTE_ADDR" => "127.0.0.1",
      "action_dispatch.request_id" => "worker-write-slow-request"
    )

    described_class.new(io) << ping_message

    payload = parse_ping_payload(io.string)
    expect(payload[:backlog]).to eq(0)
    expect(payload[:enhanced_stats][:items].size).to eq(1)
    expect(payload[:enhanced_stats][:items].first[:path_info]).to end_with("/slow")
    expect(payload[:enhanced_stats][:process]).to include(:rss_bytes, :cpu_percent)
  end

  it "passes through non-ping messages unchanged" do
    described_class.new(io) << "E11234\t{}\n"

    expect(io.string).to eq("E11234\t{}\n")
  end

  it "passes through ping messages without a pid prefix" do
    message = "p\n"
    described_class.new(io) << message

    expect(io.string).to eq(message)
  end

  it "falls back when ping json is invalid" do
    message = "p1234 \"not-json\" }\n"
    described_class.new(io) << message

    expect(io.string).to eq(message)
  end
end

RSpec.describe Puma::Enhanced::Stats::ClusterWorker do
  it "wraps worker_write with WorkerWrite before boot" do
    parent = Class.new do
      attr_reader :pipes

      def initialize(index:, master:, launcher:, pipes:, **)
        @pipes = pipes
      end
    end
    worker_class = Class.new(parent) do
      prepend Puma::Enhanced::Stats::ClusterWorker
    end
    io = StringIO.new

    worker = worker_class.new(index: 0, master: nil, launcher: nil, pipes: { worker_write: io })

    expect(worker.pipes[:worker_write]).to be_a(Puma::Enhanced::Stats::WorkerWrite)
  end
end
