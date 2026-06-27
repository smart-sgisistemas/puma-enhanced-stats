# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module CLI
        # Enrich → filter → sort pipeline for worker request items.
        class RequestPipeline
          class << self
            def process(items, collected_at:, options:)
              enriched = RequestEnricher.enrich items, collected_at: collected_at
              filtered = RequestFilter.apply enriched, options.filters
              RequestSorter.sort filtered, field: options.sort_field, dir: options.sort_dir
            end
          end
        end
      end
    end
  end
end
