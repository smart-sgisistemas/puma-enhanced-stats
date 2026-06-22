# frozen_string_literal: true

require "json"
require "puma/cluster"

RSpec.describe "enhanced stats pipe" do
  let(:registry) do
    {
      items: [{ id: "req-1" }],
      dropped_count: 2,
      truncated: true,
      backlog: 1,
      running: 1
    }
  end

  let(:options) { Puma::Launcher.new(Puma::Configuration.new).config.options }

  def worker_handle(index:, pid:)
    Puma::Cluster::WorkerHandle.new(index, pid, 0, options)
  end

  def worker_instance
    Class.new do
      attr_reader :options

      def initialize
        @options = { worker_check_interval: 0.05 }
        @enhanced_write_io = nil
      end

      def run
        :ran
      end
    end.new.tap { |instance| instance.singleton_class.prepend Puma::Enhanced::Stats::Worker }
  end

  def wire_line(pid, snapshot)
    "#{pid}\t#{JSON.generate(snapshot)}\n"
  end

  describe "wire format" do
    it "round-trips wire payload and enhanced_ping!" do
      worker = worker_handle(index: 0, pid: 42_001)
      line = wire_line(42_001, registry)
      payload = JSON.parse line.sub(/^\d+\s*/, "").chomp, symbolize_names: true

      worker.enhanced_ping! payload

      expect(worker.last_enhanced_stats[:items].first[:id]).to eq("req-1")
      expect(worker.last_enhanced_stats[:backlog]).to eq(1)
      expect(worker.last_enhanced_stats[:running]).to eq(1)
    end

    it "does not ping when pid is unknown" do
      workers = [worker_handle(index: 0, pid: 42_001)]
      line = wire_line(1, registry)
      parsed_pid = line[/^\d+/].to_i
      payload = JSON.parse line.sub(/^\d+\s*/, "").chomp, symbolize_names: true

      workers.find { |worker| worker.pid == parsed_pid }&.enhanced_ping! payload

      expect(workers.first.last_enhanced_stats[:items]).to be_empty
    end
  end

  describe Puma::Enhanced::Stats::Worker do
    describe "#run" do
      it "includes @server.stats in the wire payload" do
        read, write = IO.pipe
        worker = worker_instance
        worker.instance_variable_set(:@enhanced_write_io, write)
        worker.instance_variable_set(:@server, Struct.new(:stats).new({ backlog: 3, running: 2 }))
        worker.run
        Puma::Enhanced::Stats::CurrentRequests.register(
          "REQUEST_METHOD" => "GET",
          "PATH_INFO" => "/",
          "QUERY_STRING" => "",
          "REMOTE_ADDR" => "127.0.0.1",
          "action_dispatch.request_id" => "wire-stats"
        )
        sleep 0.15
        read.gets
        line = read.gets
        payload = JSON.parse line.sub(/^\d+\s*/, "").chomp, symbolize_names: true

        expect(payload[:backlog]).to eq(3)
        expect(payload[:running]).to eq(2)
        expect(payload[:items].first[:id]).to eq("wire-stats")
      ensure
        read.close
        write.close
        Thread.list.each do |thread|
          thread.kill if thread.name == "enhanced stats"
        end
      end

      it "writes registry snapshots to the pipe" do
        read, write = IO.pipe
        worker = worker_instance
        worker.instance_variable_set(:@enhanced_write_io, write)

        worker.run
        sleep 0.05
        line = read.gets

        expect(line).to match(/^\d+\t\{/)
      ensure
        read.close
        write.close
        Thread.list.each do |thread|
          thread.kill if thread.name == "enhanced stats"
        end
      end
    end
  end
end
