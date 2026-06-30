# frozen_string_literal: true

require "puma/cluster"
require "puma/enhanced/stats"

RSpec.describe Puma::Enhanced::Stats::Cluster do
  let(:launcher) do
    config = Puma::Configuration.new { |user| user.workers 1 }
    Puma::Launcher.new(config)
  end

  let(:cluster) { launcher.instance_variable_get(:@runner) }
  let(:options) { launcher.config.options }

  def enhanced_read_io = cluster.instance_variable_get(:@enhanced_read_io)
  def enhanced_write_io = options[:enhanced_write_io]

  def worker_handle(index:, pid:)
    Puma::Cluster::WorkerHandle.new(index, pid, 0, launcher.config.options)
  end

  def ping_worker(handle, items:, **puma_overrides)
    handle.enhanced_ping!(
      wire_row(
        index: handle.index,
        pid: handle.pid,
        items: items,
        **puma_overrides
      )
    )
  end

  let(:worker) { worker_handle(index: 0, pid: 123) }

  before do
    cluster.instance_variable_set(:@workers, [worker])
    cluster.instance_variable_set(:@phase, 0)
    cluster.instance_variable_set(:@started_at, Time.utc(2026, 1, 1, 11, 0, 0))
  end

  it "stores enhanced payloads on last_enhanced_status" do
    frozen = Time.utc(2026, 1, 1, 12, 0, 0)
    allow(Time).to receive(:now).and_return(frozen)

    ping_worker(worker, items: [{ id: "req" }], backlog: 1)

    payload = cluster.enhanced_stats

    expect(payload[:worker_status].first[:last_enhanced_checkin]).to eq(frozen.iso8601(6))
    expect(payload[:worker_status].first[:requests].first[:id]).to eq("req")
    expect(payload[:backlog_total]).to eq(1)
  end

  it "invalidates last_enhanced_status when pid changes at the same index" do
    ping_worker(worker, items: [{ id: "old" }])

    replacement = worker_handle(index: 0, pid: 456)
    ping_worker(replacement, items: [{ id: "new" }])

    cluster.instance_variable_set(:@workers, [replacement])

    items = cluster.enhanced_stats[:worker_status].first[:requests]

    expect(items.first[:id]).to eq("new")
  end

  it "ignores stale last_enhanced_status when worker is replaced" do
    ping_worker(worker, items: [{ id: "stale" }])

    cluster.instance_variable_set(
      :@workers,
      [worker_handle(index: 0, pid: 456)]
    )

    row = cluster.enhanced_stats[:worker_status].first

    expect(row[:requests]).to be_empty
    expect(row[:last_enhanced_checkin]).to be_nil
  end

  describe "#run" do
    it "creates the dedicated pipe before booting workers" do
      stub_cluster_super_run! wait: 0

      expect { cluster.run }.to change {
        cluster.instance_variable_get(:@enhanced_read_io)
      }.from(nil)

      expect(options[:enhanced_write_io]).not_to be_nil
    ensure
      enhanced_read_io&.close
      restore_cluster_super_run!
    end

    it "dispatches wire payloads via the reader thread" do
      stub_cluster_super_run!
      runner = Thread.new { cluster.run }
      sleep 0.05

      Thread.current[Puma::Enhanced::Stats::Middleware::KEY] = {
        "REQUEST_METHOD" => "GET",
        "PATH_INFO" => "/",
        "QUERY_STRING" => "",
        "REMOTE_ADDR" => "127.0.0.1",
        "action_dispatch.request_id" => "pipe-req",
        "puma.enhanced_stats.started_at" => Time.now.utc.iso8601(6)
      }

      enhanced_write_io << wire_line(
        worker.pid,
        Puma::Enhanced::Stats::Snapshot.server(
          server: instance_double(
            Puma::Server,
            stats: default_puma_stats(backlog: 3),
            options: { enhanced_stats: Puma::Enhanced::Stats::Configuration.default }
          ),
          index: worker.index
        )
      )

      20.times do
        item = worker.last_enhanced_status[:requests]&.first
        break if item&.dig(:id) == "pipe-req"

        sleep 0.05
      end

      expect(worker.last_enhanced_status[:requests].first[:id]).to eq("pipe-req")
      expect(worker.last_enhanced_status[:stats][:backlog]).to eq(3)
    ensure
      runner&.kill
      runner&.join(1)
      enhanced_read_io&.close
      restore_cluster_super_run!
    end

    it "ignores payloads for unknown worker pids" do
      stub_cluster_super_run!
      runner = Thread.new { cluster.run }
      sleep 0.05

      enhanced_write_io << wire_line(999, {})
      sleep 0.05

      expect(worker.last_enhanced_status[:requests]).to be_empty
    ensure
      runner&.kill
      runner&.join(1)
      enhanced_read_io&.close
      restore_cluster_super_run!
    end

    it "stops the reader when the pipe closes" do
      stub_cluster_super_run!
      runner = Thread.new { cluster.run }
      sleep 0.05
      enhanced_write_io.close
      sleep 0.05
    ensure
      runner&.kill
      runner&.join(1)
      enhanced_read_io&.close
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
