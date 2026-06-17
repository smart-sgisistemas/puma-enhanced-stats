# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module CLI
        # Builds SUMMARY rows from aggregated worker +puma+ stats.
        #
        # Each {Line} carries a label, display value, optional bar ratio, and
        # severity level (+:ok+, +:warn+, +:crit+).
        class SummaryAggregator
          # One SUMMARY row.
          #
          # @!attribute label [String]
          # @!attribute value [String, Integer]
          # @!attribute ratio [Float, nil]
          # @!attribute level [Symbol]
          # @!attribute backlog [Boolean]
          Line = Struct.new :label, :value, :ratio, :level, :backlog, keyword_init: true

          # @param payload [Hash{Symbol => Object}] enhanced-stats JSON
          # @return [SummaryAggregator]
          def initialize(payload) = (@payload = payload; @workers = payload[:workers] || []; @summary = payload[:summary] || {})

          # @return [Array<Line>]
          def lines
            reporting = @summary[:workers_reporting].to_i
            total = @summary[:workers_total].to_i
            in_flight = @summary[:requests_in_flight].to_i
            dropped = @summary[:requests_dropped_total].to_i

            backlog_sum = sum_puma :backlog
            running_sum = sum_puma :running
            max_threads_sum = sum_puma :max_threads
            pool_sum = sum_puma :pool_capacity

            reporting_level = reporting.zero? && total.positive? ? :crit : (reporting < total ? :warn : :ok)
            dropped_level = dropped.positive? ? :warn : :ok

            backlog_ratio = max_threads_sum.positive? ? backlog_sum.to_f / max_threads_sum : 0.0
            backlog_level = if backlog_sum >= max_threads_sum && max_threads_sum.positive?
                              :crit
                            elsif backlog_sum.positive?
                              :warn
                            else
                              :ok
                            end

            threads_ratio = max_threads_sum.positive? ? running_sum.to_f / max_threads_sum : 0.0
            threads_level = if saturated_worker? || threads_ratio >= 0.9
                              :crit
                            elsif threads_ratio >= 0.7
                              :warn
                            else
                              :ok
                            end

            pool_ratio = max_threads_sum.positive? ? pool_sum.to_f / max_threads_sum : 0.0
            pool_level = if pool_sum.zero? && max_threads_sum.positive?
                           :crit
                         elsif pool_ratio < 0.3
                           :warn
                         else
                           :ok
                         end

            [
              Line.new(label: "Workers reporting", value: "#{reporting} / #{total}", level: reporting_level),
              Line.new(label: "Requests in-flight", value: in_flight.to_s,
                       ratio: nil, level: :ok, backlog: false),
              Line.new(label: "Dropped total", value: dropped.to_s, level: dropped_level),
              Line.new(label: "Backlog (global)", value: backlog_sum.to_s,
                       ratio: backlog_ratio, level: backlog_level, backlog: true),
              Line.new(label: "Threads in use", value: "#{running_sum} / #{max_threads_sum}",
                       ratio: threads_ratio, level: threads_level),
              Line.new(label: "Pool capacity free", value: "#{pool_sum} / #{max_threads_sum}",
                       ratio: pool_ratio, level: pool_level)
            ]
          end

          private

          def sum_puma(key) = @workers.sum { |worker| worker.dig(:puma, key).to_i }

          def saturated_worker?
            @workers.any? do |worker|
              puma = worker[:puma] || {}
              running = puma[:running].to_i
              max = puma[:max_threads].to_i
              max.positive? && running >= max
            end
          end
        end
      end
    end
  end
end
