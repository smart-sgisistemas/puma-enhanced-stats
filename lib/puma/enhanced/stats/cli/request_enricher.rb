# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module CLI
        # Adds derived +elapsed+ field to request items.
        class RequestEnricher
          class << self
            def enrich(items, collected_at:)
              Array(items).map do |item|
                item.merge(
                  "elapsed" => Format.elapsed(collected_at, item["started_at"])
                )
              end
            end
          end
        end
      end
    end
  end
end
