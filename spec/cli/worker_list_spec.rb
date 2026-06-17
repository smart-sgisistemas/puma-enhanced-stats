# frozen_string_literal: true

require "puma/enhanced/stats/cli/worker_list"
require "puma/enhanced/stats/cli/options"

RSpec.describe Puma::Enhanced::Stats::CLI::WorkerList do
  let(:workers) do
    [
      { "index" => 0, "puma" => { "backlog" => 1 }, "process" => { "cpu_percent" => 1, "rss_bytes" => 100 } },
      { "index" => 1, "puma" => { "backlog" => 9 }, "process" => { "cpu_percent" => 9, "rss_bytes" => 900 } }
    ]
  end

  it "filters by worker index" do
    options = Puma::Enhanced::Stats::CLI::Options.new.tap { |o| o.worker = 1 }
    result = described_class.prepare(workers, options)

    expect(result.map { |worker| worker["index"] }).to eq([1])
  end

  it "sorts by cpu, rss, backlog, and index" do
    %w[cpu rss backlog index].each do |key|
      options = Puma::Enhanced::Stats::CLI::Options.new.tap { |o| o.sort = key }
      result = described_class.prepare(workers, options)
      expect(result.first["index"]).to eq(key == "index" ? 0 : 1)
    end
  end
end
