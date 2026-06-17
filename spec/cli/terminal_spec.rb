# frozen_string_literal: true

require "puma/enhanced/stats/cli/terminal"

RSpec.describe Puma::Enhanced::Stats::CLI::Terminal do
  after do
    described_class.size_override = nil
    described_class.tty_override = nil
    described_class.reset_resize!
  end

  it "uses size override when set" do
    described_class.size_override = [30, 100]

    expect(described_class.size).to eq([30, 100])
  end

  it "falls back to defaults when not a TTY" do
    described_class.tty_override = false

    expect(described_class.size).to eq([24, 80])
  end

  it "tracks SIGWINCH resize pending flag" do
    described_class.resize_pending = true
    expect(described_class.resize_pending).to be(true)
    described_class.reset_resize!
    expect(described_class.resize_pending).to be(false)
  end

  it "clears the screen when attached to a TTY" do
    described_class.tty_override = true

    expect { described_class.clear }.to output("\e[H\e[J").to_stdout
  end

  it "registers SIGWINCH when available" do
    handler = nil
    allow(Signal).to receive(:list).and_return("WINCH" => 28)
    allow(Signal).to receive(:trap).with("WINCH") { |&block| handler = block }

    described_class.trap_winch!
    handler.call

    expect(described_class.resize_pending).to be(true)
  end

  it "skips SIGWINCH when the signal is unavailable" do
    allow(Signal).to receive(:list).and_return({})

    expect(Signal).not_to receive(:trap)
    described_class.trap_winch!
  end

  it "falls back when winsize is unavailable" do
    described_class.tty_override = true
    console = double("IO.console")
    allow(IO).to receive(:console).and_return(console)
    allow(console).to receive(:winsize).and_raise(StandardError)

    expect(described_class.size).to eq([24, 80])
  end

  it "reads winsize from the console on a TTY" do
    described_class.tty_override = true
    console = double("IO.console", winsize: [30, 100])
    allow(IO).to receive(:console).and_return(console)

    expect(described_class.size).to eq([30, 100])
  end

  it "detects stdout TTY status without overrides" do
    described_class.tty_override = nil
    allow($stdout).to receive(:tty?).and_return(true)

    expect(described_class.tty?).to be(true)
  end

  it "treats unavailable signals as unsupported" do
    allow(Signal).to receive(:list).and_raise(StandardError)

    expect { described_class.trap_winch! }.not_to raise_error
  end

  it "skips clearing when not attached to a TTY" do
    described_class.tty_override = false

    expect { described_class.clear }.not_to output(/\e/).to_stdout
  end
end
