# frozen_string_literal: true

source "https://rubygems.org"

gemspec

if (puma_version = ENV["PUMA_VERSION"]) && !puma_version.empty?
  gem "puma", "= #{puma_version}"
end

if (rails_version = ENV["RAILS_VERSION"]) && !rails_version.empty?
  gem "rails", "= #{rails_version}"
end

gem "rake", "~> 13.0"
gem "rspec", "~> 3.0"
gem "json_schemer", "~> 2.0"
