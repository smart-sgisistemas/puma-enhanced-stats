# frozen_string_literal: true

if ENV["COVERAGE"]
  require "simplecov"

  SimpleCov.start do
    enable_coverage :branch
    add_filter "/spec/"
    add_filter "version.rb"
    add_group "Lib", "lib"
    track_files "lib/**/*.rb"
    minimum_coverage line: 100, branch: 90
  end
end

require_relative "support/rails_test_app"
RailsTestApp.boot!

Dir[File.join(__dir__, "support", "**", "*.rb")].sort.each do |f|
  next if f.end_with?("rails_test_app.rb")

  require f
end

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.filter_run_exclusions[:integration] = true if ENV["SKIP_INTEGRATION"]

  config.after(:each, :integration) do
    IntegrationServer.reset_gem_state!
  end
end
