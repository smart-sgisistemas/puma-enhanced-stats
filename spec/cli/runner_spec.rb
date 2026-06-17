# frozen_string_literal: true

require "puma/enhanced/stats/cli/runner"

RSpec.describe Puma::Enhanced::Stats::CLI::Runner do
  let(:payload) do
    {
      "schema_version" => 1,
      "meta" => { "worker_check_interval_seconds" => 1 },
      "summary" => {},
      "workers" => []
    }
  end

  let(:fetcher) do
    instance_double(
      Puma::Enhanced::Stats::CLI::Fetcher,
      fetch: payload,
      master_pid: nil
    )
  end

  before do
    allow(Puma::Enhanced::Stats::CLI::Fetcher).to receive(:new).and_return(fetcher)
    allow(Puma::Enhanced::Stats::CLI::Terminal).to receive(:trap_winch!)
    allow(Puma::Enhanced::Stats::CLI::Terminal).to receive(:clear)
    allow(Puma::Enhanced::Stats::CLI::Terminal).to receive(:tty?).and_return(false)
    allow(Puma::Enhanced::Stats::CLI::Terminal).to receive(:size).and_return([24, 100])
    allow(Puma::Enhanced::Stats::CLI::HostMetrics).to receive(:reset_cpu_sample!)
    allow(Puma::Enhanced::Stats::CLI::HostMetrics).to receive(:read).and_return(Puma::Enhanced::Stats::CLI::HostMetrics::EMPTY)
  end

  it "prints help" do
    expect { described_class.run(["--help"]) }.to raise_error(SystemExit)
  end

  it "prints json when requested" do
    expect { described_class.run(["--json"]) }
      .to output(/"schema_version": 1/).to_stdout
  end

  it "returns 1 when fetch fails" do
    allow(fetcher).to receive(:fetch).and_raise(Puma::Enhanced::Stats::CLI::Fetcher::Error, "boom")

    expect(described_class.run([])).to eq(1)
  end

  it "renders a dashboard frame with SYSTEM by default" do
    expect { described_class.run(["-w", "100"]) }
      .to output(/SYSTEM/).to_stdout
  end

  it "hides SYSTEM with --no-top" do
    expect { described_class.run(["-T", "-w", "100"]) }
      .to output(a_string_matching(/SUMMARY/)).to_stdout
    expect { described_class.run(["-T", "-w", "100"]) }
      .not_to output(a_string_matching(/SYSTEM/)).to_stdout
  end

  it "renders request-only output" do
    rich_payload = payload.merge(
      "workers" => [
        {
          "index" => 0,
          "puma" => { "backlog" => 1, "pool_capacity" => 3, "max_threads" => 5, "running" => 2 },
          "requests" => { "items" => [{ "elapsed_ms" => 1200, "method" => "GET", "path_info" => "/slow" }] }
        }
      ]
    )
    allow(fetcher).to receive(:fetch).and_return(rich_payload)

    expect { described_class.run(["--request-only", "-w", "100"]) }
      .to output(a_string_matching(/WORKERS.*WORKER 0.*\/slow/m)).to_stdout
  end

  it "exits watch loop on interrupt" do
    frames = 0
    allow_any_instance_of(described_class).to receive(:render_frame).and_wrap_original do |method, *args|
      frames += 1
      raise Interrupt if frames >= 2

      method.call(*args)
    end

    expect(described_class.run(["--watch", "-w", "100"])).to eq(0)
  end

  it "clears the screen and redraws on resize while watching" do
    frames = 0
    allow_any_instance_of(described_class).to receive(:render_frame).and_wrap_original do |method, *args|
      frames += 1
      raise Interrupt if frames >= 3

      method.call(*args)
    end
    allow(Puma::Enhanced::Stats::CLI::Terminal).to receive(:tty?).and_return(true)
    allow(Puma::Enhanced::Stats::CLI::Terminal).to receive(:resize_pending).and_return(false, true)

    expect(described_class.run(["--watch", "-w", "100"])).to eq(0)
    expect(Puma::Enhanced::Stats::CLI::Terminal).to have_received(:clear).at_least(:once)
  end

  it "uses the default worker check interval when meta is missing" do
    allow(fetcher).to receive(:fetch).and_return({ "schema_version" => 1, "workers" => [] })
    runner = described_class.new
    allow(runner).to receive(:sleep)

    expect(runner.send(:worker_check_interval, { "meta" => {} })).to eq(5)
  end

  it "prints a trailing newline when the frame does not end with one" do
    frames = 0
    allow_any_instance_of(described_class).to receive(:render_frame) do
      frames += 1
      raise Interrupt if frames >= 2

      "frame-without-newline"
    end

    expect { described_class.run(["--watch", "-w", "100"]) }
      .to output("frame-without-newline\n").to_stdout
  end

  it "does not add an extra newline when the frame already ends with one" do
    frames = 0
    allow_any_instance_of(described_class).to receive(:render_frame) do
      frames += 1
      raise Interrupt if frames >= 2

      "frame-with-newline\n"
    end

    expect { described_class.run(["--watch", "-w", "100"]) }
      .to output("frame-with-newline\n").to_stdout
  end
end
