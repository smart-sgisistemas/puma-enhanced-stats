# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module CLI
        # Filters and sorts worker entries for dashboard renderers.
        #
        # Honors {Options#worker} and {Options#sort}.
        module WorkerList
          module_function

          # @param workers [Array<Hash{Symbol => Object}>]
          # @param options [Options]
          # @return [Array<Hash{Symbol => Object}>]
          def prepare(workers, options) = sort_workers(filter_workers(workers, options), options)

          # @param workers [Array<Hash{Symbol => Object}>]
          # @param options [Options]
          # @return [Array<Hash{Symbol => Object}>]
          def filter_workers workers, options
            return workers unless options.worker.is_a?(Integer)

            workers.select { |worker| worker[:index].to_i == options.worker.to_i }
          end

          # @param workers [Array<Hash{Symbol => Object}>]
          # @param options [Options]
          # @return [Array<Hash{Symbol => Object}>]
          def sort_workers workers, options
            key = options.sort.to_s
            workers.sort_by do |worker|
              puma = worker[:puma] || {}
              process = worker[:process] || {}
              case key
              when "cpu" then [-process[:cpu_percent].to_f, worker[:index].to_i]
              when "rss" then [-process[:rss_bytes].to_i, worker[:index].to_i]
              when "backlog" then [-puma[:backlog].to_i, worker[:index].to_i]
              else [worker[:index].to_i]
              end
            end
          end
        end
      end
    end
  end
end
