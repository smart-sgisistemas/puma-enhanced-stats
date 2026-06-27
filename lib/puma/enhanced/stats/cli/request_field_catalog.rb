# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module CLI
        # Canonical request table column order.
        module RequestFieldCatalog
          PRIMARY = %w[elapsed id method path_info remote_ip].freeze
          RESERVED = %w[id started_at session].freeze

          module_function

          def discover(items)
            custom = []
            session = []
            items.each do |item|
              item.each_key do |key|
                next if RESERVED.include?(key) || PRIMARY.include?(key)

                custom << key unless custom.include?(key)
              end
              (item["session"] || {}).each_key do |key|
                field = "session.#{key}"
                session << field unless session.include?(field)
              end
            end
            PRIMARY + custom + session
          end
        end
      end
    end
  end
end
