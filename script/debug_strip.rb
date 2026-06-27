#!/usr/bin/env ruby
# frozen_string_literal: true

require "set"
require "timeout"

load File.expand_path("strip_optional_parens.rb", __dir__)

Dir.glob(File.expand_path("../{lib,spec}/**/*.rb", __dir__)).sort.each do |path|
  begin
    Timeout.timeout(2) do
      strip_optional_parens(File.read(path))
    end
    puts "ok: #{path}"
  rescue Timeout::Error
    puts "TIMEOUT: #{path}"
    break
  rescue StandardError => e
    puts "ERROR #{path}: #{e.message}"
    break
  end
end
