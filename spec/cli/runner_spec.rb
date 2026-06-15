# frozen_string_literal: true

require "puma/enhanced/stats/cli/runner"

RSpec.describe Puma::Enhanced::Stats::CLI::Runner do
  it "prints help" do
    expect { described_class.run(["--help"]) }.to raise_error(SystemExit)
  end

  it "prints json when requested" do
    payload = { "schema_version" => 1 }
    fetcher = instance_double(Puma::Enhanced::Stats::CLI::Fetcher, fetch: payload, master_pid: nil)
    allow(Puma::Enhanced::Stats::CLI::Fetcher).to receive(:new).and_return(fetcher)

    expect { described_class.run(["--url", "http://127.0.0.1:9293", "--token", "x", "--json"]) }
      .to output(/"schema_version": 1/).to_stdout
  end
end
