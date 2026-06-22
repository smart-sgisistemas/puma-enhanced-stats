# frozen_string_literal: true

RSpec.describe Puma::Enhanced::Stats::Worker do
  let(:worker) do
    Class.new do
      attr_reader :options

      def initialize
        @options = { worker_check_interval: 10 }
      end

      def run
        :puma_run
      end
    end.new.tap { |instance| instance.singleton_class.prepend described_class }
  end

  describe "#initialize" do
    it "resolves enhanced_write_io from the launcher runner" do
      pipe = instance_double(IO)
      runner = instance_double(Puma::Cluster, enhanced_write_io: pipe)
      launcher = instance_double(Puma::Launcher, runner: runner)
      instance = Class.new { def initialize(**); end }.new

      described_class.instance_method(:initialize).bind(instance).call(
        index: 0,
        master: 1,
        launcher: launcher,
        pipes: {}
      )

      expect(instance.instance_variable_get(:@enhanced_write_io)).to eq(pipe)
    end

    it "leaves enhanced_write_io nil when the runner is unavailable" do
      launcher = instance_double(Puma::Launcher, runner: nil)
      instance = Class.new { def initialize(**); end }.new

      described_class.instance_method(:initialize).bind(instance).call(
        index: 0,
        master: 1,
        launcher: launcher,
        pipes: {}
      )

      expect(instance.instance_variable_get(:@enhanced_write_io)).to be_nil
    end
  end

  describe "#run" do
    it "clears the registry and prepares the worker pipe" do
      Puma::Enhanced::Stats::CurrentRequests.register(
        "REQUEST_METHOD" => "GET",
        "PATH_INFO" => "/",
        "QUERY_STRING" => "",
        "REMOTE_ADDR" => "127.0.0.1",
        "action_dispatch.request_id" => "worker-boot-request"
      )

      read, write = IO.pipe
      worker.instance_variable_set(:@enhanced_write_io, write)

      expect(worker.run).to eq(:puma_run)
      expect(Puma::Enhanced::Stats::CurrentRequests.snapshot[:items]).to be_empty
    ensure
      write.close
      Thread.list.each do |thread|
        thread.kill if thread.name == "enhanced stats"
      end
    end

    it "skips the sender when no pipe is configured" do
      expect(worker.run).to eq(:puma_run)
      expect(Thread.list.any? { |thread| thread.name == "enhanced stats" }).to be(false)
    end

    it "stops the sender when the pipe breaks" do
      read, write = IO.pipe
      worker.instance_variable_set(:@enhanced_write_io, write)

      worker.run
      write.close
      read.close
      sleep 0.05

      expect(Thread.list.any? { |thread| thread.name == "enhanced stats" }).to be(false)
    end
  end
end
