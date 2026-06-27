# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module CLI
        # Worker sync freshness badges ([ui-spec — sync freshness]).
        class SyncFreshness
          Result = Struct.new(:badge, :title_fragment, keyword_init: true)

          class << self
            def evaluate(synced_at:, collected_at:, interval_seconds:, mode: "cluster")
              return ok "ok" if mode == "single"
              return crit "not synced" if synced_at.nil?

              age = age_seconds synced_at, collected_at
              return crit "not synced" if age.nil?

              if age <= interval_seconds
                ok "#{age}s ago"
              elsif age <= interval_seconds * 2
                warn "stale #{age}s"
              else
                crit "stale #{age}s"
              end
            end

            private

            def ok(fragment) = Result.new(badge: :ok, title_fragment: "synced #{fragment}")
            def warn(fragment) = Result.new(badge: :warn, title_fragment: "[WARN] #{fragment}")
            def crit(fragment) = Result.new(badge: :crit, title_fragment: "[CRIT] #{fragment}")

            def age_seconds(synced_at, collected_at)
              return 0 if collected_at.to_s.empty?

              synced = Time.iso8601(synced_at.to_s)
              collected = collected_at.to_s.empty? ? Time.now : Time.iso8601(collected_at.to_s)
              [(collected - synced).to_i, 0].max
            rescue ArgumentError
              nil
            end
          end
        end
      end
    end
  end
end
