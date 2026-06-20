# frozen_string_literal: true

module Puma
  module Enhanced
    module Stats
      class Railtie < Rails::Railtie
        initializer "puma_enhanced_stats.middleware" do |app|
          app.middleware.use CurrentRequestsMiddleware
        end
      end
    end
  end
end
