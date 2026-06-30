# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module Worker
        def run
          if (io = @options[:enhanced_write_io])
            Thread.new do
              Puma.set_thread_name "enhanced stats"
              loop do
                if @server
                  row = Snapshot.server(server: @server, index: @index)
                  io << "#{Process.pid}\t#{Puma::JSONSerialization.generate(row)}\n"
                end

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
