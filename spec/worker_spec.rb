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

  describe "#run" do
    it "starts the sender when enhanced_write_io is configured" do
      read, write = IO.pipe
      worker.options[:enhanced_write_io] = write

      expect(worker.run).to eq(:puma_run)
    ensure
      write.close
      read.close
      Thread.list.each do |thread|
        thread.kill if thread.name == "enhanced stats"
      end
    end

    it "skips the sender when no pipe is configured" do
      expect(worker.run).to eq(:puma_run)
      expect(Thread.list.any? { |thread| thread.name == "enhanced stats" }).to be(false)
    end

    it "does not write to the pipe until server is present" do
      read, write = IO.pipe
      worker.options[:worker_check_interval] = 0.05
      worker.options[:enhanced_write_io] = write

      worker.run
      sleep 0.15

      ready, = IO.select([read], nil, nil, 0)
      expect(ready).to be_nil
    ensure
      write.close
      read.close
      Thread.list.each do |thread|
        thread.kill if thread.name == "enhanced stats"
      end
    end

    it "stops the sender when the pipe breaks" do
      read, write = IO.pipe
      worker.options[:enhanced_write_io] = write

      worker.run
      write.close
      read.close
      sleep 0.05

      expect(Thread.list.any? { |thread| thread.name == "enhanced stats" }).to be(false)
    end
  end
end
