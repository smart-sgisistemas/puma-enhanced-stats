# frozen_string_literal: true

require "json"

require_relative "snapshot"

module Puma
  module Enhanced
    module Stats
      module Cluster
        attr_reader :enhanced_read_io, :enhanced_write_io

        def run
          @enhanced_read_io, @enhanced_write_io = Puma::Util.pipe
          @enhanced_reader_thread = Thread.new do
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
          @enhanced_reader_thread&.join 1
        end

        def worker *args
          @enhanced_read_io.close if @enhanced_read_io
          super
        end

        def enhanced_stats
          Snapshot.new(workers: @workers, worker_check_interval: @options[:worker_check_interval]).to_h
        end
      end
    end
  end
end
