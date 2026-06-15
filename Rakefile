# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

namespace :spec do
  RSpec::Core::RakeTask.new(:unit) do |t|
    t.rspec_opts = "--tag ~integration"
  end

  RSpec::Core::RakeTask.new(:integration) do |t|
    t.rspec_opts = "--tag integration"
  end

  desc "Run all specs with SimpleCov coverage report"
  task :coverage do
    ENV["COVERAGE"] = "true"
    Rake::Task["spec"].invoke
    puts "Coverage report: coverage/index.html"
  end
end

task default: :spec

desc "Generate YARD API documentation"
task :yard do
  sh "bundle exec yard doc lib"
end
