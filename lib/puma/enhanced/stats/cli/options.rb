# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      module CLI
        # Parsed command-line flags for {Runner}.
        #
        # Populated by {Runner#parse} from +OptionParser+. Connection flags mirror
        # +pumactl+ (-S, -C, -T).
        #
        # @see Runner
        class Options
          # @!attribute [rw] state_path
          #   Path to the Puma state file (-S).
          # @!attribute [rw] control_url
          #   Control socket URL (-C), e.g. +tcp://127.0.0.1:9293+.
          # @!attribute [rw] url
          #   HTTP control URL (--url).
          # @!attribute [rw] token
          #   Control app auth token (-T).
          # @!attribute [rw] watch
          #   Enable auto-refresh (-w / --watch).
          # @!attribute [rw] top
          #   Show SYSTEM and PROCESSES blocks (--top).
          # @!attribute [rw] json_mode
          #   Print raw JSON instead of the dashboard (--json).
          # @!attribute [rw] no_color
          #   Disable ANSI colors (--no-color).
          # @!attribute [rw] worker
          #   Filter a single worker index (--worker N).
          # @!attribute [rw] compact
          #   Use two-column worker grid (--compact).
          # @!attribute [rw] sort
          #   Sort key for workers and PROCESSES: +cpu+, +rss+, +backlog+, or +index+.
          # @!attribute [rw] width
          #   Fixed terminal width in columns (--width), for CI/tests.
          attr_accessor :state_path, :control_url, :url, :token,
                        :watch, :top, :json_mode, :no_color,
                        :worker, :compact, :sort, :width

          # @return [void]
          def initialize
            @sort = "index"
          end

          # @return [Boolean]
          def json_mode? = @json_mode

          # @return [Boolean]
          def watch? = @watch

          # @return [Boolean]
          def top? = @top

          # @return [Boolean]
          def compact? = @compact

          # @return [Boolean]
          def no_color? = @no_color
        end
      end
    end
  end
end
