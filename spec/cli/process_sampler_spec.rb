# frozen_string_literal: true

require "puma/enhanced/stats/cli/process_sampler"

RSpec.describe Puma::Enhanced::Stats::CLI::ProcessSampler do
  let(:runner) { instance_double(Puma::Enhanced::Stats::CLI::ProcessSampler::Runner) }

  before do
    described_class.send(:remove_instance_variable, :@runner) if described_class.instance_variable_defined?(:@runner)
    stub_const("Puma::Enhanced::Stats::CLI::ProcessSampler::Runner", Class.new)
    allow(Puma::Enhanced::Stats::CLI::ProcessSampler::Runner).to receive(:new).and_return runner
    allow(described_class).to receive(:runner).and_return runner
    allow(Puma::Enhanced::Stats::CLI::CgroupMemory).to receive(:total_bytes).and_return 16_000_000_000
  end

  after do
    described_class.send(:remove_instance_variable, :@runner) if described_class.instance_variable_defined?(:@runner)
  end

  it "samples a single pid via ps batch output" do
    allow(runner).to receive(:ps_batch).with("48201").and_return "48201 18.2  2.6 104857\n"

    sample = described_class.sample 48_201

    expect(sample.cpu_percent).to eq 18.2
    expect(sample.mem_percent).to eq 2.6
    expect(sample.rss_bytes).to eq 104_857 * 1024
  end

  it "returns nil metrics when ps output is missing" do
    allow(runner).to receive(:ps_batch).with("99999").and_return ""

    sample = described_class.sample 99_999

    expect(sample.cpu_percent).to be_nil
    expect(sample.rss_bytes).to be_nil
  end

  it "samples workers and master pid together" do
    allow(runner).to receive(:ps_batch).with("48201,48202,48200").and_return <<~PS
      48201 18.2  2.6 104857
      48202 42.7  2.5 101376
      48200  0.3  0.8 32768
    PS

    workers = [{ "pid" => 48_201 }, { "pid" => 48_202 }]
    samples = described_class.sample_all(workers, master_pid: 48_200)

    expect(samples.keys).to contain_exactly 48_201, 48_202, 48_200
    expect(samples[48_202].cpu_percent).to eq 42.7
  end

  it "exposes memory capacity from CgroupMemory" do
    expect(described_class.memory_capacity_bytes).to eq 16_000_000_000
  end

  it "returns top outsiders excluding known puma pids" do
    allow(runner).to receive(:ps_outsiders).and_return <<~PS
      9912 72.4  2.8 215040 sidekiq
      48201 18.2  2.6 104857 puma
      7001 12.0  1.0 65536 postgres
    PS

    outsiders = described_class.top_outsiders(exclude_pids: [48_201], limit: 2)

    expect(outsiders.map(&:pid)).to eq [9912, 7001]
    expect(outsiders.first.command).to eq "sidekiq"
  end
end
