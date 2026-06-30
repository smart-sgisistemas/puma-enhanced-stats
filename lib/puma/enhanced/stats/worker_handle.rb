# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module WorkerHandle
        def initialize *args
          @last_enhanced_status = {
            stats: Puma::Server::STAT_METHODS.to_h { |key| [key, 0] },
            requests: []
          }
          super
        end

        attr_reader :last_enhanced_checkin, :last_enhanced_status

        def enhanced_ping! payload
          @last_enhanced_checkin = Time.now.utc
          @last_enhanced_status = {
            stats: payload[:stats],
            requests: payload[:requests]
          }
        end
      end
    end
  end
end
