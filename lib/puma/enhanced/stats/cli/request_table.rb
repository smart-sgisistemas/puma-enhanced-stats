# frozen_string_literal: true

require_relative "format"

module Puma
  module Enhanced
    module Stats
      module CLI
        # Renders the in-flight request table inside a worker box.
        #
        # Fits as many columns as the configured width allows; overflow fields
        # appear as nested +└+ lines under each request row.
        class RequestTable
          RESERVED = %i[id started_at elapsed_ms session].freeze
          PRIMARY_ORDER = %i[elapsed_ms method path_info remote_ip].freeze

          # @param items [Array<Hash{Symbol => Object}>]
          # @param inner_width [Integer]
          # @return [RequestTable]
          def initialize(items, inner_width:) = (@items = items; @inner_width = inner_width)

          # @param max_items [Integer]
          # @return [Array<String>]
          def render max_items:
            return ["No in-flight requests"] if @items.empty?

            primary, overflow = column_layout
            visible = @items.first max_items
            hidden_count = @items.size - visible.size
            lines = header_lines primary
            visible.each { |item| lines.concat item_lines item, primary, overflow }
            lines << "… +#{hidden_count} more requests" if hidden_count.positive?
            lines
          end

          # @return [Integer] overflow field count from {#column_layout}
          def overflow_field_count = column_layout.last.size

          private

          def column_layout = @column_layout ||= split_columns(discover_fields)

          def discover_fields
            request_fields = []
            session_fields = []
            @items.each do |item|
              item.each_key do |key|
                next if RESERVED.include? key

                request_fields << key unless request_fields.include? key
              end
              (item[:session] || {}).each_key do |key|
                field = "session.#{key}"
                session_fields << field unless session_fields.include? field
              end
            end
            PRIMARY_ORDER + (request_fields - PRIMARY_ORDER) + session_fields
          end

          def split_columns all_fields
            primary_fields = []
            all_fields.each do |field|
              trial_fields = primary_fields + [field]
              headers = trial_fields.map { |name| header_for name }
              rows = @items.map { |item| trial_fields.map { |name| cell_value item, name } }
              widths = Format.column_widths [headers] + rows
              break if Format.table_row(rows.first || headers, widths).length > @inner_width - 2

              primary_fields = trial_fields
            end
            overflow = all_fields - primary_fields
            [primary_fields.map { |name| [name, header_for(name)] }, overflow]
          end

          def header_for field
            case field
            when :elapsed_ms then "ELAPSED"
            when :method then "METHOD"
            when :path_info then "PATH"
            when :remote_ip then "REMOTE"
            when /\Asession\.(.+)\z/ then Regexp.last_match(1).upcase[0, 8]
            else field.to_s.upcase.tr("_", " ")[0, 10]
            end
          end

          def header_lines primary
            return [] if primary.empty?

            headers = primary.map(&:last)
            widths = Format.column_widths [headers]
            ["IN-FLIGHT (#{@items.size})", Format.table_row(headers, widths)]
          end

          def item_lines item, primary, overflow
            row = primary.map { |field, _header| cell_value item, field }
            widths = Format.column_widths [primary.map(&:last), row]
            lines = [Format.table_row(row, widths)]
            overflow.each do |field|
              value = Format.truncate cell_value(item, field), @inner_width - 6
              lines << "  └ #{field}: #{value}"
            end
            lines
          end

          def cell_value item, field
            if field == :elapsed_ms
              Format.elapsed_ms item[:elapsed_ms]
            elsif field.start_with? "session."
              item.dig :session, field.split(".", 2).last.to_sym
            else
              item[field]
            end.to_s
          end
        end
      end
    end
  end
end
