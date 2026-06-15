# frozen_string_literal: true

require "pastel"

module Puma
  module Enhanced
    module Stats
      module CLI
        # ANSI colors via Pastel; disabled with +--no-color+ or on non-TTY stdout.
        #
        # Maps utilization ratios to +:ok+, +:warn+, and +:crit+ levels for
        # {Bar} segments and badge text.
        #
        # @see Bar
        # @see Options#no_color?
        class Colors
          # Pastel color names per severity level.
          LEVELS = {
            ok: :green,
            warn: :yellow,
            crit: :red,
            muted: :dim
          }.freeze

          # @param options [Options]
          def initialize options
            @enabled = !options.no_color? && Terminal.tty?
            @pastel = Pastel.new enabled: @enabled
          end

          # Maps a ratio to a severity level.
          #
          # @param ratio [Numeric] value in +0.0..1.0+
          # @param backlog [Boolean] when true, any positive ratio is +:crit+
          # @return [Symbol] +:ok+, +:warn+, or +:crit+
          def level ratio, backlog: false
            return :crit if backlog && ratio.positive?
            return :crit if ratio >= 0.9
            return :warn if ratio >= 0.7

            :ok
          end

          # @param text [String]
          # @param level [Symbol]
          # @return [String] ANSI-decorated or plain text
          def paint text, level
            color = LEVELS.fetch level
            @pastel.decorate text, color
          end

          # @param level [Symbol]
          # @return [String] filled bar character (+█+)
          def bar_segment level
            paint "█", level
          end

          # @return [String] empty bar character (+░+)
          def empty_segment
            @pastel.decorate "░", :dim
          end

          # @param text [String]
          # @param level [Symbol] defaults to +:muted+
          # @return [String]
          def decorate text, level = :muted
            paint text, level
          end
        end
      end
    end
  end
end
