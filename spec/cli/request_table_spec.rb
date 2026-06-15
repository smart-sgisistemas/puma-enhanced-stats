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
end
