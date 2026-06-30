# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module CLI
        # Dashboard vs modal routing and keyboard handling.
        class ScreenManager
          def initialize(options)
            @options = options
          end

          def render_modal(budget)
            case @options.modal
            when :design then DesignScreen.new.render @options, budget
            when :sort then SortScreen.new.render @options, budget
            when :filter then FilterScreen.new.render @options, budget
            when :help then HelpScreen.new.render @options, budget
            end
          end

          def modal_open? = !@options.modal.nil?

          # @return [Boolean] true when key consumed
          def handle(key, scroll:, payload:)
            return handle_modal key if modal_open?

            handle_dashboard key, scroll: scroll, payload: payload
          end

          private

          def handle_modal(key)
            case key
            when "\e", "q" then @options.modal = nil
            when "n", "\e[C" then @options.help_tab += 1 if @options.modal == :help
            when "p", "\e[D" then @options.help_tab -= 1 if @options.modal == :help
            end
            true
          end

          def handle_dashboard(key, scroll:, payload:)
            case key
            when "r" then @options.force_refresh = true; @options.dirty = true
            when "d" then @options.modal = :design
            when "o" then @options.modal = :sort
            when "f" then @options.modal = :filter
            when "?", "h" then @options.modal = :help
            when "l" then cycle_layout!
            when "i" then cycle_request_display!
            when "t" then @options.no_top = !@options.no_top; @options.dirty = true
            when "O" then @options.show_outsiders = !@options.show_outsiders?; @options.dirty = true
            when "W" then save_prefs!
            when "x" then @options.filters = {}; @options.dirty = true
            when "j" then bump_request_scroll scroll, payload, 1
            when "k" then bump_request_scroll scroll, payload, -1
            when "[" then page_request_scroll(scroll, payload, -1)
            when "]" then page_request_scroll scroll, payload, 1
            when /\A[0-9]\z/ then focus_worker(scroll, key.to_i)
            else return false
            end
            true
          end

          def cycle_layout!
            modes = FrameRenderer::LAYOUTS
            index = modes.index(@options.frame_layout) || 0
            @options.frame_layout = modes[(index + 1) % modes.size]
            @options.dirty = true
          end

          def cycle_request_display!
            modes = %w[auto inline stack]
            index = modes.index(@options.request_display) || 0
            @options.request_display = modes[(index + 1) % modes.size]
            @options.dirty = true
          end

          def save_prefs!
            UserConfig.save! @options
            @options.save_message = "saved preferences to ~/.pesrc"
            @options.dirty = false
          end

          def focus_worker(scroll, index)
            scroll.focus_worker = index
            @options.focus_worker = index
            @options.dirty = true
          end

          def bump_request_scroll(scroll, payload, delta)
            worker = current_worker(scroll, payload)
            scroll.bump_request! worker["index"], delta if worker
          end

          def page_request_scroll(scroll, payload, delta)
            worker = current_worker(scroll, payload)
            scroll.page_request! worker["index"], 5, delta if worker
          end

          def current_worker(scroll, payload)
            view = PayloadView.wrap(payload)
            workers = view.workers
            index = scroll.focus_worker || @options.focus_worker || workers.dig(0, "index")
            workers.find { |w| w["index"].to_i == index.to_i } || workers.first
          end
        end
      end
    end
  end
end
