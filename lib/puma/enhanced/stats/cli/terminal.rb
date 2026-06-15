# frozen_string_literal: true

require "io/console"

module Puma
  module Enhanced
    module Stats
      module CLI
        # Terminal dimensions, TTY detection, screen clear, and SIGWINCH handling.
        #
        # Used by {Runner} for layout and +--watch+ mode. Class-level overrides
        # (+size_override+, +tty_override+) support tests.
        #
        # @see Runner
        class Terminal
          # Default row count when not attached to a TTY.
          DEFAULT_ROWS = 24
          # Default column count when not attached to a TTY.
          DEFAULT_COLS = 80

          class << self
            # @return [[Integer, Integer], nil] test override for rows/cols tuple
            attr_accessor :size_override
            # @return [Boolean, nil] test override for {Terminal.tty?}
            attr_accessor :tty_override
            # @return [Boolean] set by SIGWINCH; cleared by {Terminal.reset_resize!}
            attr_accessor :resize_pending

            # @return [[Integer, Integer]] +[rows, cols]+
            def size
              return size_override if size_override

              if tty?
                rows, cols = IO.console.winsize
                [rows, cols]
              else
                [DEFAULT_ROWS, DEFAULT_COLS]
              end
            rescue StandardError
              [DEFAULT_ROWS, DEFAULT_COLS]
            end

            # @param options [Options, nil] when set, {Options#width} overrides detected cols
            # @return [Integer] usable column count
            def cols options = nil
              _, width = size
              options&.width || width
            end

            # @return [Integer]
            def rows = size.first

            # @return [Boolean]
            def tty?
              return tty_override unless tty_override.nil?

              $stdout.tty?
            end

            # Clears the screen when attached to a TTY (+--watch+).
            #
            # @return [void]
            def clear
              return unless tty?

              require "tty-screen"
              Tty::Screen.clear
            rescue LoadError
              print "\e[H\e[J"
            end

            # Registers SIGWINCH to set {Terminal.resize_pending} for redraw-without-refetch.
            #
            # @return [void]
            def trap_winch!
              return unless signal_available? "WINCH"

              Signal.trap "WINCH" do
                self.resize_pending = true
              end
            end

            # @param name [String] signal name, e.g. +"WINCH"+
            # @return [Boolean]
            def signal_available? name
              Signal.list.key? name
            rescue StandardError
              false
            end

            # @return [void]
            def reset_resize!
              self.resize_pending = false
            end
          end
        end
      end
    end
  end
end
