# frozen_string_literal: true

require "json"

module Puma
  module Enhanced
    module Stats
      module Worker
        def initialize index:, master:, launcher:, pipes:, app: nil
          @enhanced_write_io = launcher.runner&.enhanced_write_io
          super
        end

        def run
          CurrentRequests.reset!
          if @enhanced_write_io
            Thread.new do
              Puma.set_thread_name "enhanced stats"
              loop do
                payload = CurrentRequests.snapshot.merge @server&.stats || {}
                @enhanced_write_io << "#{Process.pid}\t#{JSON.generate(payload)}\n"
                sleep @options[:worker_check_interval]
              rescue StandardError
                break
              end
            end
          end
          super
        end
      end
    end
  end
end
