# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module CLI
        # Parsed command-line flags and runtime dashboard preferences for {Runner}.
        #
        # Defaults are applied first, then {UserConfig}  ~/.pesrc, then CLI flags.
        class Options
          # @!attribute [rw] no_watch
          #   Single snapshot to stdout; default is watch mode.
          # @!attribute [rw] no_top
          #   Hides TOP and PROCESSES blocks.
          # @!attribute [rw] json
          #   Print raw JSON instead of the dashboard.
          # @!attribute [rw] no_color
          #   Disable ANSI colors.
          # @!attribute [rw] no_rc
          #   Ignore ~/.pesrc.
          # @!attribute [rw] sort_process
          #   PROCESSES / worker box sort: severity, cpu, rss, backlog, index.
          # @!attribute [rw] width
          #   Fixed terminal width for tests/CI.
          # @!attribute [rw] frame_layout
          #   stacked, two_column, split, grid, focus, compact.
          # @!attribute [rw] request_display
          #   auto, inline, stack.
          # @!attribute [rw] show_outsiders
          #   Show OUTSIDE PUMA panel.
          # @!attribute [rw] focus_worker
          #   Focused worker index for layout focus mode.
          # @!attribute [rw] filters
          #   Active request filters (field => value).
          # @!attribute [rw] sort_field
          #   Request table sort field.
          # @!attribute [rw] sort_dir
          #   Request table sort direction (asc/desc).
          # @!attribute [rw] state_path
          #   Puma state file (-S).
          # @!attribute [rw] control_url
          #   Control app URL (-C).
          # @!attribute [rw] token
          #   Control app auth token (-T).
          # @!attribute [rw] config_path
          #   Puma config file (-F).
          attr_accessor :no_watch, :no_top, :json, :no_color, :no_rc,
                        :sort_process, :width, :frame_layout, :request_display,
                        :show_outsiders, :focus_worker, :filters,
                        :sort_field, :sort_dir,
                        :state_path, :control_url, :token, :config_path,
                        :modal, :help_tab, :dirty, :save_message, :force_refresh

          def initialize
            @no_watch = false
            @no_top = false
            @json = false
            @no_color = false
            @no_rc = false
            @sort_process = "severity"
            @frame_layout = "stacked"
            @request_display = "auto"
            @show_outsiders = false
            @focus_worker = nil
            @filters = {}
            @sort_field = "elapsed"
            @sort_dir = "desc"
            @show_top = true
            @modal = nil
            @help_tab = 0
            @dirty = false
            @force_refresh = false
          end

          # @return [Boolean] watch mode (default on unless --no-watch)
          def watch? = !@no_watch

          # @return [Boolean] show TOP and PROCESSES sections
          def top? = @show_top && !@no_top

          # @return [Boolean]
          def show_outsiders? = @show_outsiders

          # @param value [String, nil]
          def show_top=(value)
            @show_top = truthy?(value)
          end

          # @return [Boolean]
          def show_top? = @show_top

          # Connection overrides for {ControlDiscovery}.
          # @return [Hash{Symbol=>Object}]
          def connection_overrides
            overrides = {}
            overrides[:state_path] = @state_path if @state_path && !@state_path.empty?
            overrides[:control_url] = @control_url if @control_url && !@control_url.empty?
            overrides[:token] = @token unless @token.nil?
            overrides[:config_path] = @config_path if @config_path && !@config_path.empty?
            overrides
          end

          private

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
