# frozen_string_literal: true

RSpec.describe Puma::Enhanced::Stats::PumaCompat do
  it "falls back to the legacy pipe ping prefix" do
    stub_const("Puma::Const::PipeRequest", Module.new)

    expect(described_class.pipe_ping_prefix).to eq("p")
  end

  it "builds status apps with positional token init" do
    launcher = double("launcher")
    klass = Class.new do
      attr_reader :token

      def initialize(_launcher, token)
        @token = token
      end
    end

    allow(described_class).to receive(:status_app_keyword_init?).and_return(false)

    app = described_class.status_app(klass, launcher, token: "secret")
    expect(app.token).to eq("secret")
  end

  it "reads before_worker_boot metadata from hook entries" do
    hook = { block: -> { :ok }, cluster_only: false }

    expect(described_class.before_worker_boot_block(hook).call).to eq(:ok)
    expect(described_class.before_worker_boot_cluster_only?(hook)).to be(false)
    expect(described_class.before_worker_boot_cluster_only?(-> {})).to be(true)
  end

  it "reads hooks from configuration objects without _options" do
    hook = -> {}
    config = double(
      "config",
      options: double(default_options: { before_worker_boot: [hook] })
    )
    allow(config).to receive(:respond_to?).with(:_options).and_return(false)

    expect(described_class.before_worker_boot_hooks(config)).to eq([hook])
  end

  it "extracts before_worker_boot blocks from raw procs" do
    proc = -> { :booted }

    expect(described_class.before_worker_boot_block(proc).call).to eq(:booted)
  end
end
