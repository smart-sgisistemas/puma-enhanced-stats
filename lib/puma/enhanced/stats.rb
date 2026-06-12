# frozen_string_literal: true

require_relative "stats/version"

module Puma
  module Enhanced
    # Extended statistics collection and reporting for Puma.
    module Stats
      class Error < StandardError; end
    end
  end
end
