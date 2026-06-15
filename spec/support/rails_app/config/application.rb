# frozen_string_literal: true

require_relative "boot"
require "rails"
require "active_support/railtie"
require "action_dispatch/railtie"
require "action_controller/railtie"

module TestRailsApp
  class Application < Rails::Application
    config.root = File.expand_path("..", __dir__)
    config.load_defaults 7.0
    config.eager_load = false
    config.consider_all_requests_local = true
    config.secret_key_base = "0" * 64
    config.session_store :cookie_store, key: "_puma_enhanced_stats_test"
    config.hosts.clear
  end
end
