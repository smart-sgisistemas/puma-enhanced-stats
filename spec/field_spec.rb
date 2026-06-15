# frozen_string_literal: true

RSpec.describe Puma::Enhanced::Stats::Field do
  let(:env) do
    {
      "REQUEST_METHOD" => "POST",
      "PATH_INFO" => "/items",
      "rack.session" => { "user_id" => "7" }
    }
  end

  let(:rack_session) { env["rack.session"] }

  it "reads values from source via [] when no block is given" do
    field = described_class.new(name: :PATH_INFO)
    expect(field.extract(env)).to eq("/items")
  end

  it "reads session values from source via [] when no block is given" do
    field = described_class.new(name: :user_id)
    expect(field.extract(rack_session)).to eq("7")
  end

  it "calls block with env when block is given" do
    field = described_class.new(name: :url, block: ->(e) { e["PATH_INFO"] })
    expect(field.extract(env)).to eq("/items")
  end

  it "calls block with rack.session when block is given" do
    field = described_class.new(name: :user_id, block: ->(session) { session["user_id"] })
    expect(field.extract(rack_session)).to eq("7")
  end

  it "uses built-in request extractors from configuration defaults" do
    field = Puma::Enhanced::Stats::Configuration.new.fields_for(:request).find { |f| f.name == "method" }
    expect(field.extract(env)).to eq("POST")
  end
end
