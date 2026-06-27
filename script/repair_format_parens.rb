#!/usr/bin/env ruby
# frozen_string_literal: true

ROOT = File.expand_path("..", __dir__)

Dir.glob(File.join(ROOT, "lib/puma/enhanced/stats/cli/**/*.rb")).sort.each do |path|
  text = File.read(path)
  updated = text.gsub(/format (%"[^"]*"(?:, [^)]+)?)\)/, "format \\1")
  updated = updated.gsub(
    /Time\.iso8601 worker\["synced_at"\]\.to_s \+ 0\)/,
    "Time.iso8601(worker[\"synced_at\"].to_s + 0)"
  )
  updated = updated.gsub(
    /Time\.iso8601 value\.to_s\.strftime "%H:%M:%S"/,
    'Time.iso8601(value.to_s).strftime "%H:%M:%S"'
  )
  next if updated == text

  File.write(path, updated)
  puts path
end
