# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module CLI
        # Maps metrics to ok / info / warn / crit badges.
        module AlertLevel
          module_function

          def for_ratio(ratio, backlog: false)
            ratio = ratio.to_f
            return :crit if backlog && ratio.positive?
            return :crit if ratio > 0.9
            return :warn if ratio >= 0.75

            :ok
          end

          def for_backlog(value)
            value.to_i.positive? ? :crit : :ok
          end

          def for_truncated(flag)
            flag ? :info : :ok
          end

          def for_dropped(count)
            count.to_i.positive? ? :warn : :ok
          end

          def aggregate_worker_sync(workers, collected_at:, interval_seconds:, mode: "cluster")
            crit = 0
            warn = 0

            Array(workers).each do |worker|
              badge = SyncFreshness.evaluate(
                synced_at: worker["synced_at"],
                collected_at: collected_at,
                interval_seconds: interval_seconds,
                mode: mode
              ).badge
              case badge
              when :crit then crit += 1
              when :warn then warn += 1
              end
            end

            if crit.positive?
              { level: :crit, suffix: "stale #{crit}" }
            elsif warn.positive?
              { level: :warn, suffix: "stale #{warn}" }
            else
              { level: :ok, suffix: :ok }
            end
          end
        end
      end
    end
  end
end
