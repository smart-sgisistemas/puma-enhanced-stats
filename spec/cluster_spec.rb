# frozen_string_literal: true

require "json"
require "puma/cluster"

RSpec.describe Puma::Enhanced::Stats::Cluster do
  let(:launcher) do
    config = Puma::Configuration.new { |user| user.workers 1 }
    Puma::Launcher.new(config)
  end

  let(:cluster) { launcher.instance_variable_get(:@runner) }

  def worker_handle(index:, pid:)
    Puma::Cluster::WorkerHandle.new(index, pid, 0, launcher.config.options)
  end

  def default_stats backlog: 0
    Puma::Server::STAT_METHODS.to_h { |key| [key, 0] }.merge(backlog: backlog)
  end

  let(:worker) { worker_handle(index: 0, pid: 123) }

  before do
    cluster.instance_variable_set(:@workers, [worker])
  end

  it "stores enhanced payloads on last_enhanced_stats" do
    frozen = Time.utc(2026, 1, 1, 12, 0, 0)
    allow(Time).to receive(:now).and_return(frozen)

    worker.enhanced_ping!(
      default_stats(backlog: 1).merge(
        items: [{ id: "req" }],
        dropped_count: 0,
        truncated: false
      )
    )

    payload = cluster.enhanced_stats

    expect(payload[:workers].first[:synced_at]).to eq(frozen.iso8601)
    expect(payload[:workers].first[:requests][:items].first[:id]).to eq("req")
    expect(payload[:summary][:backlog_total]).to eq(1)
  end

  it "invalidates last_enhanced_stats when pid changes at the same index" do
    worker.enhanced_ping!(
      default_stats.merge(
        items: [{ id: "old" }],
        dropped_count: 0,
        truncated: false
      )
    )

    replacement = worker_handle(index: 0, pid: 456)
    replacement.enhanced_ping!(
      default_stats.merge(
        items: [{ id: "new" }],
        dropped_count: 0,
        truncated: false
      )
    )

    cluster.instance_variable_set(:@workers, [replacement])

    items = cluster.enhanced_stats[:workers].first[:requests][:items]

    expect(items.first[:id]).to eq("new")
  end

  it "ignores stale last_enhanced_stats when worker is replaced" do
    worker.enhanced_ping!(
      default_stats.merge(
        items: [{ id: "stale" }],
        dropped_count: 0,
        truncated: false
      )
    )

    cluster.instance_variable_set(
      :@workers,
      [worker_handle(index: 0, pid: 456)]
    )

    row = cluster.enhanced_stats[:workers].first

    expect(row[:requests][:items]).to be_empty
    expect(row[:synced_at]).to be_nil
  end

  it "ignores enhanced_ping! errors" do
    expect { worker.enhanced_ping!(nil) }.not_to raise_error
  end

  describe "#run" do
    def stub_cluster_super_run! wait: 0.5
      Puma::Cluster.class_eval do
        alias_method :__stats_test_original_cluster_run, :run unless method_defined?(:__stats_test_original_cluster_run, false)

        define_method(:run) do
          sleep wait
        end
      end
    end

    def restore_cluster_super_run!
      Puma::Cluster.class_eval do
        alias_method :run, :__stats_test_original_cluster_run
        remove_method :__stats_test_original_cluster_run
      end
    end

    it "creates the dedicated pipe before booting workers" do
      stub_cluster_super_run! wait: 0

      expect { cluster.run }.to change {
        cluster.enhanced_read_io
      }.from(nil)
    ensure
      cluster.enhanced_read_io&.close
      cluster.instance_variable_get(:@enhanced_reader_thread)&.join(1)
      restore_cluster_super_run!
    end

    it "dispatches wire payloads via the reader thread" do
      stub_cluster_super_run!
      runner = Thread.new { cluster.run }
      sleep 0.05

      cluster.enhanced_write_io << "#{worker.pid}\t#{JSON.generate(
        items: [{ id: "pipe-req" }],
        dropped_count: 0,
        truncated: false,
        backlog: 3
      )}\n"
      sleep 0.05

      expect(worker.last_enhanced_stats[:items].first[:id]).to eq("pipe-req")
      expect(worker.last_enhanced_stats[:backlog]).to eq(3)
    ensure
      runner&.kill
      runner&.join(1)
      cluster.enhanced_read_io&.close
      cluster.instance_variable_get(:@enhanced_reader_thread)&.join(1)
      restore_cluster_super_run!
    end

    it "ignores payloads for unknown worker pids" do
      stub_cluster_super_run!
      runner = Thread.new { cluster.run }
      sleep 0.05

      cluster.enhanced_write_io << "999\t#{JSON.generate(items: [{ id: "orphan" }])}\n"
      sleep 0.05

      expect(worker.last_enhanced_stats[:items]).to be_empty
    ensure
      runner&.kill
      runner&.join(1)
      cluster.enhanced_read_io&.close
      cluster.instance_variable_get(:@enhanced_reader_thread)&.join(1)
      restore_cluster_super_run!
    end

    it "stops the reader when the pipe closes" do
      stub_cluster_super_run!
      runner = Thread.new { cluster.run }
      sleep 0.05
      cluster.enhanced_write_io.close
      sleep 0.05
    ensure
      runner&.kill
      runner&.join(1)
      cluster.enhanced_read_io&.close
      cluster.instance_variable_get(:@enhanced_reader_thread)&.join(1)
      restore_cluster_super_run!
    end

    it "cleans up when pipe setup fails" do
      stub_cluster_super_run! wait: 0
      allow(Puma::Util).to receive(:pipe).and_raise(Errno::EMFILE)

      expect { cluster.run }.to raise_error(Errno::EMFILE)
    ensure
      restore_cluster_super_run!
    end

    it "cleans up when the reader thread fails to start" do
      stub_cluster_super_run! wait: 0
      allow(Thread).to receive(:new).and_raise(RuntimeError, "thread failed")

      expect { cluster.run }.to raise_error(RuntimeError, "thread failed")
    ensure
      restore_cluster_super_run!
    end
  end

  describe "#worker" do
    def stub_cluster_super_worker!
      Puma::Cluster.class_eval do
        alias_method :__stats_test_original_worker, :worker unless method_defined?(:__stats_test_original_worker, false)

        define_method(:worker) do |*|
        end
      end
    end

    def restore_cluster_super_worker!
      Puma::Cluster.class_eval do
        alias_method :worker, :__stats_test_original_worker
        remove_method :__stats_test_original_worker
      end
    end

    it "closes the inherited read end in child workers" do
      read, _write = IO.pipe
      cluster.instance_variable_set(:@enhanced_read_io, read)
      stub_cluster_super_worker!

      cluster.worker(0, Process.pid)

      expect(read).to be_closed
    ensure
      restore_cluster_super_worker!
    end

    it "no-ops when the pipe read end is missing" do
      cluster.instance_variable_set(:@enhanced_read_io, nil)
      stub_cluster_super_worker!

      expect { cluster.worker(0, Process.pid) }.not_to raise_error
    ensure
      restore_cluster_super_worker!
    end
  end
end
