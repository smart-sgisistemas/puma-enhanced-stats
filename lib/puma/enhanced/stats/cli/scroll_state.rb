# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module CLI
        # Session scroll offsets for requests and workers ([ADR 0004]).
        class ScrollState
          attr_accessor :focus_worker, :worker_offset
          attr_reader :request_offset

          def initialize
            @request_offset = Hash.new(0)
            @worker_offset = 0
            @focus_worker = nil
          end

          def request_offset_for(worker_index) = @request_offset[worker_index.to_i]

          def bump_request!(worker_index, delta)
            @request_offset[worker_index.to_i] = [@request_offset[worker_index.to_i] + delta, 0].max
          end

          def page_request!(worker_index, page_size, delta)
            bump_request! worker_index, delta * page_size
          end

          def clamp!(payload)
            workers = payload["workers"] || []
            workers.each do |worker|
              index = worker["index"].to_i
              count = worker.dig("requests", "items")&.size.to_i
              max_offset = [count - 1, 0].max
              @request_offset[index] = [@request_offset[index], max_offset].min
            end
            max_worker = [workers.size - 1, 0].max
            @worker_offset = [@worker_offset, max_worker].min
          end
        end
      end
    end
  end
end
