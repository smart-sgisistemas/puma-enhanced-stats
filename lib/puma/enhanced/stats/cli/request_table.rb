# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module CLI
        # Renders the in-flight request table inside a worker box.
        class RequestTable
          RESERVED = %w[id started_at elapsed_ms session elapsed].freeze
          PRIMARY_ORDER = %w[elapsed_ms method path_info remote_ip].freeze

          def initialize(items, inner_width:, display_mode: "auto", offset: 0)
            @items = items
            @inner_width = inner_width
            @display_mode = display_mode
            @offset = offset
          end

          def render(max_items:)
            return ["No in-flight requests"] if @items.empty?
            return stack_only max_items if @inner_width <= 1

            mode = resolved_mode
            if mode == "stack"
              return stack_render max_items
            end

            primary, overflow = column_layout
            visible = @items[@offset, max_items] || []
            hidden_count = @items.size - visible.size - @offset
            headers = primary.map(&:last)
            rows = visible.map { |item| primary.map { |field, _| cell_value(item, field) } }
            widths = Format.column_widths [headers] + rows
            lines = header_lines primary, visible.size, widths: widths
            visible.each { |item| lines.concat item_lines item, primary, overflow, widths: widths }
            lines << "… +#{hidden_count} more requests" if hidden_count.positive?
            lines << "… +#{hidden_count} more below (j)" if hidden_count.positive? && @offset.positive?
            lines
          end

          def overflow_field_count
            return stack_field_count if resolved_mode == "stack"

            column_layout.last.size
          end

          private

          def resolved_mode
            return @display_mode unless @display_mode == "auto"

            primary, = column_layout
            primary.empty? ? "stack" : "inline"
          end

          def stack_only(max_items)
            visible = @items[@offset, max_items] || []
            lines = []
            visible.each { |item| lines.concat stack_item_lines(item) }
            lines
          end

          def stack_render(max_items)
            visible = @items[@offset, max_items] || []
            hidden_count = @items.size - visible.size - @offset
            lines = header_lines([], visible.size, stack: true)
            visible.each { |item| lines.concat stack_item_lines(item) }
            lines << "… +#{hidden_count} more below (j)" if hidden_count.positive?
            lines
          end

          def stack_item_lines(item)
            lines = []
            path = item["path_info"].to_s
            lines.concat Format.wrap_indented("  └ path_info: ", path, @inner_width)
            stack_fields(item).each do |field|
              next if field == "path_info"

              lines.concat Format.wrap_indented(
                "  └ #{header_for(field)}: ",
                cell_value(item, field),
                @inner_width
              )
            end
            lines
          end

          def stack_fields(item)
            fields = discover_fields - %w[path_info]
            fields.reject { |f| f == "elapsed_ms" && item.key?("elapsed") }
          end

          def stack_field_count
            return 0 if @items.empty?

            stack_fields(@items.first).size
          end

          def column_layout
            @column_layout ||= split_columns(discover_fields)
          end

          def discover_fields
            request_fields = []
            session_fields = []
            @items.each do |item|
              item.each_key do |key|
                next if RESERVED.include?(key)

                request_fields << key unless request_fields.include?(key)
              end
              (item["session"] || {}).each_key do |key|
                field = "session.#{key}"
                session_fields << field unless session_fields.include?(field)
              end
            end
            PRIMARY_ORDER + (request_fields - PRIMARY_ORDER) + session_fields
          end

          def split_columns(all_fields)
            primary_fields = []
            all_fields.each do |field|
              trial_fields = primary_fields + [field]
              headers = trial_fields.map { |name| header_for(name) }
              rows = @items.map { |item| trial_fields.map { |name| cell_value(item, name) } }
              widths = Format.column_widths [headers] + rows
              break if Format.display_length(Format.table_row(rows.first || headers, widths)) > @inner_width - 2

              primary_fields = trial_fields
            end
            overflow = all_fields - primary_fields
            [primary_fields.map { |name| [name, header_for(name)] }, overflow]
          end

          def header_lines(primary, visible_count, stack: false, widths: nil)
            total = @items.size
            range = total.zero? ? "0" : "#{@offset + 1}/#{total}"
            header = "IN-FLIGHT (#{range})  sort: elapsed  filter: —"
            return [header] if stack || primary.empty?

            headers = primary.map(&:last)
            widths ||= Format.column_widths [headers]
            [header, Format.table_row(headers, widths)]
          end

          def item_lines(item, primary, overflow, widths:)
            row = primary.map { |field, _header| cell_value(item, field) }
            lines = [Format.table_row(row, widths)]
            overflow.each do |field|
              lines.concat Format.wrap_indented(
                "  └ #{header_for(field)}: ",
                cell_value(item, field),
                @inner_width
              )
            end
            lines
          end

          def header_for(field)
            case field
            when "elapsed_ms", "elapsed" then "ELAPSED"
            when "method" then "METHOD"
            when "path_info" then "PATH"
            when "remote_ip" then "REMOTE"
            when /\Asession\.(.+)\z/ then Regexp.last_match(1).upcase.tr("_", " ")[0, 8]
            else field.upcase.tr("_", " ")[0, 10]
            end
          end

          def cell_value(item, field)
            if field == "elapsed_ms"
              Format.elapsed_ms item["elapsed_ms"]
            elsif field == "elapsed"
              item["elapsed"]
            elsif field.start_with?("session.")
              item.dig("session", field.split(".", 2).last)
            else
              item[field]
            end.to_s
          end
        end
      end
    end
  end
end
