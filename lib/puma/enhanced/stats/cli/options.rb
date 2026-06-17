# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module CLI
        # Parsed command-line flags for {Runner}.
        #
        # SYSTEM/PROCESSES blocks are shown by default; pass +--no-top+ to hide them.
        class Options
          # @!attribute [rw] watch
          #   When +true+, redraw on +worker_check_interval+ and handle SIGWINCH.
          # @!attribute [rw] no_top
          #   Hides SYSTEM and PROCESSES blocks.
          # @!attribute [rw] json
          #   Print raw JSON instead of the dashboard.
          # @!attribute [rw] no_color
          #   Disable ANSI colors.
          # @!attribute [rw] worker
          #   Filter to a single worker index.
          # @!attribute [rw] compact
          #   Two-column worker grid (at most two workers, width &gt;= 120).
          # @!attribute [rw] sort
          #   Sort key: +cpu+, +rss+, +backlog+, or +index+ (default).
          # @!attribute [rw] width
          #   Fixed terminal width for tests/CI.
          # @!attribute [rw] request_only
          #   Minimal view: worker summary and in-flight requests only.
          attr_accessor :watch, :no_top, :json, :no_color,
                        :worker, :compact, :sort, :width, :request_only

          def initialize
            @sort = "index"
          end

          # @return [Boolean] +false+ when +--no-top+ was passed
          def top? = !@no_top
        end
      end
    end
  end
end
