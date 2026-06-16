# frozen_string_literal: true

require "puma/enhanced/stats/cli/request_table"
require "puma/enhanced/stats/cli/colors"
require "puma/enhanced/stats/cli/options"

RSpec.describe Puma::Enhanced::Stats::CLI::RequestTable do
  let(:options) { Puma::Enhanced::Stats::CLI::Options.new.tap { |o| o.no_color = true } }
  let(:colors) { Puma::Enhanced::Stats::CLI::Colors.new(options) }
  let(:items) do
    [{
      "id" => "abc",
      "elapsed_ms" => 4500,
      "method" => "GET",
      "path_info" => "/reports",
      "remote_ip" => "10.0.0.1",
      "shop_id" => "BR-001",
      "session" => { "user_id" => "42" }
    }]
  end

  it "nests overflow fields when columns do not fit" do
    table = described_class.new(items, inner_width: 40, colors: colors)
    lines = table.render(max_items: 1)

    expect(lines.join("\n")).to include("ELAPSED").and include("PATH")
    expect(lines.join("\n")).to include("└ shop_id:")
    expect(lines.join("\n")).to include("└ session.user_id:")
  end

  it "shows empty and truncated request tables" do
    empty = described_class.new([], inner_width: 80, colors: colors)
    expect(empty.render(max_items: 5)).to eq(["No in-flight requests"])

    wide = described_class.new([items.first, items.first], inner_width: 200, colors: colors)
    output = wide.render(max_items: 1).join("\n")
    expect(output).to include("+1 more requests")
    expect(output).to include("SHOP ID")
  end

  it "omits flat columns when the table is too narrow" do
    table = described_class.new(items, inner_width: 1, colors: colors)
    lines = table.render(max_items: 1)

    expect(lines.join("\n")).not_to include("IN-FLIGHT")
    expect(lines.join("\n")).to include("└")
  end
end
