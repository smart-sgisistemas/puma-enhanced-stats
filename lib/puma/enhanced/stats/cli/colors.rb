# frozen_string_literal: true

require "pastel"

module Puma
  module Enhanced
    module Stats
      module CLI
        # ANSI severity colors for dashboard bars and badges.
        class Colors
          LEVELS = {
            ok: :green,
            info: :cyan,
            warn: :yellow,
            crit: :red,
            muted: :dim
          }.freeze

          def initialize(options)
            @pastel = Pastel.new(enabled: !options.no_color && Terminal.tty?)
          end

          def enabled? = @pastel.enabled?

          def level(ratio, backlog: false)
            AlertLevel.for_ratio(ratio, backlog: backlog)
          end

          def paint(text, level = :ok)
            @pastel.decorate(text, LEVELS.fetch(level))
          end

          def badge(level)
            paint(level.to_s.upcase, level)
          end
        end
      end
    end
  end
end
