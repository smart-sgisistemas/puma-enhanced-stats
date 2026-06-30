# frozen_string_literal: true

require "json"

module Puma
  module Enhanced
    module Stats
      module Cluster
        def run
          @enhanced_read_io, @options[:enhanced_write_io] = Puma::Util.pipe
          Thread.new do
            Puma.set_thread_name "enhanced stats rd"
            loop do
              line = @enhanced_read_io.gets
              break unless line

              pid = line[/^\d+/].to_i
              payload = JSON.parse line.sub(/^\d+\s*/, "").chomp, symbolize_names: true

              if w = @workers.find { |x| x.pid == pid }
                w.enhanced_ping! payload
              end
            rescue StandardError
              next
            end
          end
          super
        ensure
          @enhanced_read_io&.close
        end

        def worker *args
          @enhanced_read_io.close if @enhanced_read_io
          super
        end

        def enhanced_stats = Snapshot.cluster(workers: @workers, phase: @phase, started_at: @started_at)
      end
    end
  end
end
