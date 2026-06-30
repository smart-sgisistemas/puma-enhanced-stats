# frozen_string_literal: true

require "puma/enhanced/stats/cli/runner"

RSpec.describe Puma::Enhanced::Stats::CLI::Runner do
  let(:payload) do
    JSON.parse(File.read(File.expand_path("../fixtures/stub/mixed-cluster.json", __dir__)))
  end

  let(:fetcher) do
    instance_double(
      Puma::Enhanced::Stats::CLI::Fetcher,
      fetch: payload,
      master_pid: 48_200,
      worker_check_interval: 5
    )
  end

  before do
    allow(Puma::Enhanced::Stats::CLI::Fetcher).to receive(:new).and_return fetcher
    allow(Puma::Enhanced::Stats::CLI::UserConfig).to receive(:load).and_return({})
    allow(Puma::Enhanced::Stats::CLI::Terminal).to receive :trap_winch!
    allow(Puma::Enhanced::Stats::CLI::Terminal).to receive :clear
    allow(Puma::Enhanced::Stats::CLI::Terminal).to receive(:tty?).and_return false
    allow(Puma::Enhanced::Stats::CLI::Terminal).to receive(:size).and_return [40, 80]
    allow(Puma::Enhanced::Stats::CLI::HostMetrics).to receive :reset_cpu_sample!
    allow(Puma::Enhanced::Stats::CLI::HostMetrics).to receive(:read).and_return(Puma::Enhanced::Stats::CLI::HostMetrics::EMPTY)
    allow(Puma::Enhanced::Stats::CLI::ProcessSampler).to receive(:sample_all).and_return({})
    allow(Puma::Enhanced::Stats::CLI::ProcessSampler).to receive(:top_outsiders).and_return []
  end

  it "prints help" do
    expect { described_class.run ["--help"] }.to raise_error SystemExit
  end

  it "prints json when requested" do
    expect { described_class.run ["--json", "--no-watch"] }
      .to output(/"collected_at"/).to_stdout
  end

  it "returns 1 when fetch fails" do
    allow(fetcher).to receive(:fetch).and_raise(Puma::Enhanced::Stats::CLI::Fetcher::Error, "boom")
    expect(described_class.run ["--json", "--no-watch"]).to eq 1
  end

  it "renders dashboard with SUMMARY" do
    expect { described_class.run ["--no-watch", "-w", "80", "--no-top"] }
      .to output(a_string_matching /SUMMARY/).to_stdout
  end

  it "passes connection overrides to Fetcher" do
    expect(Puma::Enhanced::Stats::CLI::Fetcher).to receive(:new)
      .with(overrides: hash_including(control_url: "http://127.0.0.1:9293"))
      .and_return fetcher

    described_class.run(["--no-watch", "--json", "-C", "http://127.0.0.1:9293"])
  end
end
