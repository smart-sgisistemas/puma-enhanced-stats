# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module CLI
        # Sorts in-flight requests.
        class RequestSorter
          class << self
            def sort(items, field: "elapsed", dir: "desc")
              sorted = Array(items).sort_by { |item| sort_key item, field }
              dir.to_s == "asc" ? sorted : sorted.reverse
            end

            private

            def sort_key(item, field)
              value = item[field]
              return value.to_s.downcase if value.is_a? String
              return value.to_f if value.is_a? Numeric

              value.to_s
            end
          end
        end
      end
    end
  end
end
