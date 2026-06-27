#!/usr/bin/env ruby
# frozen_string_literal: true

ROOT = File.expand_path("..", __dir__)

Dir.glob(File.join(ROOT, "lib/**/*.rb")).sort.each do |path|
  lines = File.read(path).lines
  changed = false
  out = lines.map do |line|
    next line if line =~ /^\s*def\s+/

    updated = line
    updated = updated.gsub(/\.join\("([^"]*)"\)/, '.join "\1"')
    updated = updated.gsub(/format\("%([^"]*)",/, 'format "%\1",')
    updated = updated.gsub(/argv\.include\?\("([^"]*)"\)/, 'argv.include? "\1"')
    updated = updated.gsub(/Time\.iso8601\(([^)]+)\)/, 'Time.iso8601 \1')
    updated = updated.gsub(/\.end_with\?\("\\n"\)/, '.end_with? "\n"')
    changed ||= updated != line
    updated
  end
  next unless changed

  File.write(path, out.join)
  puts path
end
