# frozen_string_literal: true

module RailsTestApp
  ROOT = File.expand_path("rails_app", __dir__)

  module_function

  def slow_sleep
    @slow_sleep ||= 3
  end

  def slow_sleep= value
    @slow_sleep = value
  end

  def boot!
    return if @booted

    ENV["RAILS_ENV"] = "test"
    require_relative "rails_app/config/environment"
    @booted = true
  end

  def application
    boot!
    Rails.application
  end
end
