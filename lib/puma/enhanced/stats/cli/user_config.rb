# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module CLI
        # Loads and saves user preferences from ~/.pesrc (or +PESRC+).
        #
        # Format: +key=value+ lines; +#+ comments and blank lines are ignored.
        # Applied before CLI flags via {Runner} parse order.
        class UserConfig
          Options = ::Puma::Enhanced::Stats::CLI::Options

          class << self
            # @return [String]
            def default_path
              File.expand_path(ENV.fetch("PESRC", "~/.pesrc"))
            end

            # @param path [String]
            # @return [Hash{String=>String}]
            def load(path = default_path)
              return {} unless path && File.file?(path)

              File.readlines(path, chomp: true).each_with_object({}) do |line, config|
                line = line.strip
                next if line.empty? || line.start_with?("#")

                key, value = line.split("=", 2)
                next unless key && !key.empty? && value

                config[key.strip] = value.strip
              end
            end

            # @param options [Options]
            # @param config [Hash{String=>String}]
            # @return [Options]
            def apply!(options, config)
              return options if config.nil? || config.empty?

              apply_if_present(options, :frame_layout, config["frame_layout"])
              apply_if_present(options, :request_display, config["request_display"])
              apply_show_top(options, config["show_top"])
              apply_if_present(options, :show_outsiders, config["show_outsiders"]) { |v| truthy?(v) }
              apply_if_present(options, :sort_process, config["sort.process"])
              apply_if_present(options, :sort_field, config["sort.field"])
              apply_if_present(options, :sort_dir, config["sort.dir"])
              apply_if_present(options, :focus_worker, config["focus_worker"]) { |v| Integer(v) }
              apply_filters!(options, config)
              options
            end

            # @param options [Options]
            # @param path [String]
            def save!(options, path = default_path)
              File.write(path, serialize(options))
            end

            # @param options [Options]
            # @return [String]
            def serialize(options)
              lines = []
              lines << "frame_layout=#{options.frame_layout}"
              lines << "request_display=#{options.request_display}"
              lines << "show_top=#{options.show_top? ? 'true' : 'false'}"
              lines << "show_outsiders=#{options.show_outsiders? ? 'true' : 'false'}"
              lines << "sort.process=#{options.sort_process}"
              lines << "sort.field=#{options.sort_field}"
              lines << "sort.dir=#{options.sort_dir}"
              lines << "focus_worker=#{options.focus_worker}" unless options.focus_worker.nil?
              options.filters.each do |field, value|
                lines << "filter.#{field}=#{value}"
              end
              "#{lines.join "\n"}\n"
            end

            private

            def apply_if_present(options, attribute, value)
              return if value.nil? || value.to_s.empty?

              options.public_send("#{attribute}=", block_given? ? yield(value) : value)
            end

            def apply_show_top(options, value)
              return if value.nil? || value.to_s.empty?

              options.show_top = value
            end

            def apply_filters!(options, config)
              config.each do |key, value|
                next unless key.start_with?("filter.")

                field = key.delete_prefix("filter.")
                next if field.empty?

                options.filters[field] = value
              end
            end

            def truthy?(value)
              case value.to_s.strip.downcase
              when "1", "true", "yes", "on" then true
              when "0", "false", "no", "off" then false
              else !value.nil? && value != ""
              end
            end
          end
        end
      end
    end
  end
end
