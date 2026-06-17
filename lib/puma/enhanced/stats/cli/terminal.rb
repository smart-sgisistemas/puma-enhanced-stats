# frozen_string_literal: true

require "io/console"

module Puma
  module Enhanced
    module Stats
      module CLI
        # Terminal size, TTY detection, and watch-mode helpers.
        #
        # Class-level overrides (+size_override+, +tty_override+) support tests.
        # +resize_pending+ is set by a SIGWINCH trap while watching (default).
        class Terminal
          DEFAULT_ROWS = 24
          DEFAULT_COLS = 80

          class << self
            attr_accessor :size_override, :tty_override, :resize_pending

            # @return [Array(Integer, Integer)] +[rows, cols]+
            def size
              return size_override if size_override
              return [DEFAULT_ROWS, DEFAULT_COLS] unless tty?

              IO.console.winsize
            rescue StandardError
              [DEFAULT_ROWS, DEFAULT_COLS]
            end

            # @return [Boolean]
            def tty?
              return tty_override unless tty_override.nil?

              $stdout.tty?
            end

            # Clears the screen when attached to a TTY.
            #
            # @return [void]
            def clear = (print("\e[H\e[J") if tty?)

            # Registers a SIGWINCH handler that sets {resize_pending}.
            #
            # @return [void]
            def trap_winch!
              return unless Signal.list.key? "WINCH"

              Signal.trap "WINCH" do
                self.resize_pending = true
              end
            rescue StandardError
              nil
            end

            # @return [void]
            def reset_resize! = self.resize_pending = false
          end
        end
      end
    end
  end
end
