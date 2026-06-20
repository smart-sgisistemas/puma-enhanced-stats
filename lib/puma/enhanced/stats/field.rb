# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      class Field
        attr_reader :name, :block

        def initialize name:, block: nil
          @name = name.to_s
          @block = block
        end

        def extract source
          if block
            block.call source
          else
            source[name] || source[name.to_s] || source[name.to_sym]
          end
        end
      end
    end
  end
end
