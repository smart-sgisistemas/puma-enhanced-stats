# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      class Snapshot
        class << self
          def server(server:, index: 0) = new(server: server, index: index).server_row
          def single(server:) = new(server: server).single_payload
          def cluster(workers:, phase:, started_at:) = new(workers: workers, phase: phase, started_at: started_at).cluster_payload
        end

        def initialize server: nil, workers: nil, phase: nil, started_at: nil, index: 0
          @server = server
          @workers = workers
          @phase = phase || 0
          @started_at = started_at
          @index = index
          @collected_at = Time.now.iso8601(6)
        end

        def server_row
          config = @server.options[:enhanced_stats] || Configuration.default
          stats = @server.stats.transform_keys(&:to_sym)

          {
            index: @index,
            pid: Process.pid,
            stats: stats,
            requests: Thread.list.filter_map do |thread|
              env = thread[Middleware::KEY]
              next unless env

              config.fields_for(:request).to_h { |field|
                [field.name.to_sym, truncate(field.extract(env), config.max_field_length)]
              }.merge session: config.fields_for(:session).to_h { |field|
                [field.name.to_sym, truncate(field.extract(env.fetch("rack.session", {})), config.max_field_length)]
              }
            end
          }
        rescue StandardError
          { index: @index, pid: Process.pid, stats: {}, requests: [] }
        end

        def single_payload
          row = server_row
          pool_stats = Puma::Server::STAT_METHODS.to_h { |key| [key, 0] }.merge(row[:stats])

          {
            collected_at: @collected_at,
            **pool_stats,
            requests_in_flight: row[:requests].size,
            requests: row[:requests],
            versions: { :"puma-enhanced-stats" => VERSION }
          }
        end

        def cluster_payload
          workers = Array(@workers)
          worker_status = workers.map do |handle|
            status = handle.last_enhanced_status

            {
              index: handle.index,
              pid: handle.pid,
              phase: handle.phase,
              booted: handle.booted?,
              started_at: handle.started_at&.iso8601(6),
              last_enhanced_checkin: handle.last_enhanced_checkin&.iso8601(6),
              last_enhanced_status: status[:stats],
              requests: status[:requests]
            }
          end
          reporting = worker_status.count { |row| row[:last_enhanced_checkin] }

          {
            started_at: @started_at&.iso8601(6),
            workers: workers.size,
            phase: @phase,
            booted_workers: workers.count(&:booted?),
            old_workers: workers.count { |worker| worker.phase != @phase },
            collected_at: @collected_at,
            workers_total: worker_status.size,
            workers_reporting: reporting,
            workers_stale: worker_status.size - reporting,
            requests_in_flight: worker_status.sum { |row| row[:requests].size },
            backlog_total: worker_status.sum { |row| row[:last_enhanced_status][:backlog] },
            busy_threads_total: worker_status.sum { |row| row[:last_enhanced_status][:busy_threads] },
            max_threads_total: worker_status.sum { |row| row[:last_enhanced_status][:max_threads] },
            pool_capacity_total: worker_status.sum { |row| row[:last_enhanced_status][:pool_capacity] },
            worker_status: worker_status,
            versions: {
              puma: Puma::Const::PUMA_VERSION,
              ruby: { engine: RUBY_ENGINE, version: RUBY_VERSION, patchlevel: RUBY_PATCHLEVEL },
              :"puma-enhanced-stats" => VERSION
            }
          }
        end

        private

        def truncate value, max_length
          return nil unless value

          string = value.to_s
          return string if string.length <= max_length

          "#{string[0, max_length - 1]}…"
        end
      end
    end
  end
end
