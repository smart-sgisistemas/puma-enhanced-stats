# frozen_string_literal: true

require "io/console"

module Puma
  module Enhanced
    module Stats
      module CLI
        # Terminal size, TTY detection, alternate screen, and watch-mode helpers.
        class Terminal
          DEFAULT_ROWS = 24
          DEFAULT_COLS = 80
          ALT_ENTER = "\e[?1049h"
          ALT_LEAVE = "\e[?1049l"
          MOUSE_ENABLE = "\e[?1000h\e[?1006h"
          MOUSE_DISABLE = "\e[?1006l\e[?1000l"

          class << self
            attr_accessor :size_override, :tty_override, :resize_pending, :alternate_active

            def size
              return size_override if size_override

              return [DEFAULT_ROWS, DEFAULT_COLS] unless tty?

              IO.console.winsize
            rescue StandardError
              [DEFAULT_ROWS, DEFAULT_COLS]
            end

            def tty?
              return tty_override unless tty_override.nil?

              $stdout.tty?
            end

            def clear
              return unless tty?

              print "\e[0m\e[H\e[2J"
            end

            def restore!
              return unless tty?

              print "\e[?25h\e[0m"
              leave_alternate_screen!
            end

            def enter_alternate_screen!
              return unless tty?

              print ALT_ENTER
              print MOUSE_ENABLE
              self.alternate_active = true
            end

            def leave_alternate_screen!
              return unless tty? && alternate_active

              print MOUSE_DISABLE
              print ALT_LEAVE
              self.alternate_active = false
            end

            def trap_winch!
              return unless Signal.list.key? "WINCH"

              Signal.trap("WINCH") { self.resize_pending = true }
              nil
            rescue StandardError
              nil
            end

            def reset_resize! = self.resize_pending = false
          end
        end
      end
    end
  end
end
