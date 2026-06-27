# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module CLI
        # Filters in-flight requests by field=value.
        class RequestFilter
          class << self
            def apply(items, filters)
              return items if filters.nil? || filters.empty?

              Array(items).select do |item|
                filters.all? do |field, expected|
                  actual = value_for item, field
                  actual.to_s.downcase.include?(expected.to_s.downcase)
                end
              end
            end

            private

            def value_for(item, field)
              return item.dig("session", field.split(".", 2).last) if field.start_with? "session."

              item[field]
            end
          end
        end
      end
    end
  end
end
