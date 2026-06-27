# frozen_string_literal: true

require "io/console"

module Puma
  module Enhanced
    module Stats
      module CLI
        # Non-blocking stdin reader for watch mode.
        class Keyboard
          ARROW_KEYS = {
            "[A" => "k",
            "[B" => "j",
            "[C" => "\e[C",
            "[D" => "\e[D"
          }.freeze

          SGR_MOUSE_RE = /\A\[<(\d+);\d+;\d+[mM]\z/.freeze
          INTERRUPT_CHARS = ["\x03", "\x1a"].freeze # Ctrl+C, Ctrl+Z
          ESCAPE_WAIT = 0.05

          class << self
            def read(deadline:)
              return nil unless Terminal.tty?

              console = IO.console
              ch = read_char console
              return nil if ch.nil? || ch.empty?

              raise Interrupt if INTERRUPT_CHARS.include?(ch)

              return decode_escape(console) if ch == "\e"

              ch
            rescue Interrupt
              raise
            rescue StandardError
              nil
            end

            def refresh?
              return false unless Terminal.tty?

              ready, = IO.select([IO.console], nil, nil, 0)
              !ready.nil?
            rescue StandardError
              false
            end

            private

            def read_char(console)
              if console.respond_to?(:raw)
                console.raw(min: 1, time: 0) { console.getch }
              else
                enable_stty_cbreak!
                begin
                  console.getch
                ensure
                  restore_stty!
                end
              end
            end

            def enable_stty_cbreak!
              @saved_stty = `stty -g 2>/dev/null`.strip
              return if @saved_stty.empty?

              # Keep ISIG so Ctrl+C still raises Interrupt outside getch.
              system "stty", "-icanon", "-echo", "min", "1", "time", "0"
            end

            def restore_stty!
              return if @saved_stty.to_s.empty?

              system "stty", @saved_stty
              @saved_stty = nil
            end

            def decode_escape(console)
              buffer = +""
              deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + ESCAPE_WAIT

              while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
                break if escape_complete? buffer

                ready, = IO.select([console], nil, nil, 0.01)
                break unless ready

                buffer << read_char(console)
                break if buffer.length >= 32
              end

              decode_escape_buffer buffer
            end

            def escape_complete?(buffer)
              return false if buffer.empty?
              return true if ARROW_KEYS.key?(buffer[0, 2])
              return true if buffer.match?(SGR_MOUSE_RE)
              return true if legacy_mouse?(buffer)

              buffer.length >= 32
            end

            def decode_escape_buffer(buffer)
              return ARROW_KEYS[buffer[0, 2]] if ARROW_KEYS.key?(buffer[0, 2])

              if (match = buffer.match(SGR_MOUSE_RE))
                wheel_key = wheel_key_for(match[1].to_i)
                return wheel_key if wheel_key
              end

              if legacy_mouse?(buffer)
                wheel_key = wheel_key_for(buffer[1].ord - 32)
                return wheel_key if wheel_key
              end

              "\e"
            end

            def legacy_mouse?(buffer)
              buffer.start_with?("M") && buffer.length >= 4
            end

            def wheel_key_for(button)
              case button
              when 64, 4 then "k"
              when 65, 5 then "j"
              end
            end
          end
        end
      end
    end
  end
end
