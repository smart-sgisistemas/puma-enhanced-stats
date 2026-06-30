# frozen_string_literal: true

RSpec.describe Puma::Enhanced::Stats::Single do
  let(:runner) do
    Class.new do
      attr_accessor :server

      prepend Puma::Enhanced::Stats::Single

      def initialize(server = nil)
        @server = server
      end
    end.new(server)
  end

  describe "#enhanced_stats" do
    context "when server is absent" do
      let(:server) { nil }

      it "zero-fills pool counters" do
        payload = runner.enhanced_stats

        Puma::Server::STAT_METHODS.each do |key|
          expect(payload[key]).to eq(0)
        end
        expect(payload[:requests]).to eq([])
        expect(payload[:requests_in_flight]).to eq(0)
        expect(payload[:versions][:"puma-enhanced-stats"]).to eq(Puma::Enhanced::Stats::VERSION)
      end
    end
  end
end
