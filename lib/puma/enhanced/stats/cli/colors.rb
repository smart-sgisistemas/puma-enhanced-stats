# frozen_string_literal: true

require "pastel"

module Puma
  module Enhanced
    module Stats
      module CLI
        # ANSI severity colors for dashboard bars and badges.
        #
        # Disabled when +--no-color+ is passed or stdout is not a TTY.
        class Colors
          LEVELS = {
            ok: :green,
            warn: :yellow,
            crit: :red,
            muted: :dim
          }.freeze

          def initialize(options) = @pastel = Pastel.new(enabled: !options.no_color && Terminal.tty?)

          # Maps a ratio to +:ok+, +:warn+, or +:crit+.
          #
          # Backlog bars treat any positive ratio as +:crit+.
          def level ratio, backlog: false
            return :crit if backlog && ratio.positive?
            return :crit if ratio >= 0.9
            return :warn if ratio >= 0.7

            :ok
          end

          def paint(text, level = :ok) = @pastel.decorate(text, LEVELS.fetch(level))
        end
      end
    end
  end
end
