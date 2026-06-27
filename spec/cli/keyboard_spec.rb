# frozen_string_literal: true

require "puma/enhanced/stats/cli/keyboard"
require "puma/enhanced/stats/cli/terminal"
require "puma/enhanced/stats/cli/scroll_state"
require "puma/enhanced/stats/cli/screen_manager"

RSpec.describe Puma::Enhanced::Stats::CLI::Keyboard do
  def mock_console(chars)
    queue = chars.dup
    console = instance_double(IO)
    allow(console).to receive(:respond_to?).with(:raw).and_return true
    allow(console).to receive(:raw).with(min: 1, time: 0).and_yield
    allow(console).to receive(:getch) { queue.shift }
    console
  end

  before do
    allow(Puma::Enhanced::Stats::CLI::Terminal).to receive(:tty?).and_return true
    allow(IO).to receive(:select).and_return [[$stdin]]
  end

  it "maps SGR mouse wheel down to j" do
    console = mock_console ["\e", "[<65;10;20M"]
    allow(IO).to receive(:console).and_return console

    expect(described_class.read(deadline: Time.now.to_i + 5)).to eq "j"
  end

  it "maps SGR mouse wheel up to k" do
    console = mock_console ["\e", "[<64;3;4M"]
    allow(IO).to receive(:console).and_return console

    expect(described_class.read(deadline: Time.now.to_i + 5)).to eq "k"
  end

  it "maps legacy mouse wheel buttons to j and k" do
    legacy = ->(button, col, row) { "M#{(32 + button).chr}#{(32 + col).chr}#{(32 + row).chr}" }

    console = mock_console ["\e", legacy.call(4, 10, 5)]
    allow(IO).to receive(:console).and_return console
    expect(described_class.read(deadline: Time.now.to_i + 5)).to eq "k"

    console = mock_console ["\e", legacy.call(5, 10, 5)]
    allow(IO).to receive(:console).and_return console
    expect(described_class.read(deadline: Time.now.to_i + 5)).to eq "j"
  end

  it "scrolls in-flight requests when the wheel is used" do
    options = Puma::Enhanced::Stats::CLI::Options.new
    manager = Puma::Enhanced::Stats::CLI::ScreenManager.new options
    scroll = Puma::Enhanced::Stats::CLI::ScrollState.new
    payload = {
      "workers" => [
        { "index" => 0, "requests" => { "items" => [{}, {}, {}] } }
      ]
    }

    manager.handle("j", scroll: scroll, payload: payload)

    expect(scroll.request_offset_for(0)).to eq 1
  end
end
