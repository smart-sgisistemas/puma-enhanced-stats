#!/usr/bin/env ruby
# frozen_string_literal: true

require "set"

ROOT = File.expand_path("..", __dir__)

def endless_def_line?(line)
  line.match?(/^\s*def\s+.+=/)
end

def endless_def_lines(code)
  code.lines.each_with_index.with_object(Set.new) do |(line, index), set|
    set << index if endless_def_line?(line)
  end
end

def line_number_at(code, index)
  code[0...index].count("\n")
end

def line_prefix(code, index)
  line_start = code.rindex("\n", index - 1)
  line_start = line_start ? line_start + 1 : 0
  code[line_start...index]
end

def ambiguous_call_context?(code, start)
  prefix = line_prefix(code, start)
  return true if prefix.include?("<<")
  return true if prefix =~ /\[[^\]]*$/

  false
end

def method_call_paren?(code, start)
  before = code[0...start].rstrip
  return false if before.empty?
  return false if before =~ /\bdef\s+[\w!?]+(\s*,\s*[\w!?]+)*\s*$/
  return false if before =~ /\b(class|module|if|unless|while|until|case|for|rescue|elsif|when|not|and|or)\s*$/
  return false if before =~ /%[a-zA-Z]\s*$/
  return false unless before =~ /(?:\.|::)?[a-zA-Z_]\w*[?!]?\s*$/

  true
end

def matching_paren(code, start)
  depth = 0
  i = start
  in_str = nil
  while i < code.length
    char = code[i]
    if in_str
      if char == "\\"
        i += 2
        next
      end
      in_str = nil if char == in_str
      i += 1
      next
    end

    case char
    when '"', "'"
      in_str = char
    when "#"
      i += 1 while i < code.length && code[i] != "\n"
      next
    when "("
      depth += 1
    when ")"
      depth -= 1
      return i if depth.zero?
    end
    i += 1
  end
  nil
end

def followed_by_block?(code, finish)
  rest = code[(finish + 1)..].to_s
  same_line = rest.lines.first.to_s.lstrip
  return true if same_line.start_with?("{", "do")

  rest.lines.drop(1).each do |line|
    stripped = line.strip
    next if stripped.empty? || stripped.start_with?("#")

    return stripped.start_with?("{", "do")
  end
  false
end

def followed_by_dot?(code, finish)
  code[(finish + 1)..].to_s.lstrip.start_with?(".")
end

def strip_safe?(code, start, finish)
  inner = code[(start + 1)...finish]
  return false if inner.lstrip.start_with?("{", "|", "&")
  return false if ambiguous_call_context?(code, start)
  return false if inner.match?(/[a-zA-Z_]\w*\.[a-zA-Z_]/)
  return false if inner.match?(/[a-zA-Z_]\w*\s*:/)

  true
end

def strip_optional_parens(code)
  skip_lines = endless_def_lines(code)
  result = code.dup
  iterations = 0
  changed = true
  while changed
    iterations += 1
    raise "too many paren passes" if iterations > 1_000

    changed = false
    i = 0
    while i < result.length
      if result[i] == "(" && method_call_paren?(result, i)
        if skip_lines.include?(line_number_at(result, i))
          i += 1
          next
        end

        finish = matching_paren(result, i)
        if finish && !followed_by_block?(result, finish) && !followed_by_dot?(result, finish) && strip_safe?(result, i, finish)
          inner = result[(i + 1)...finish]
          result = result[0...i] + " " + inner + result[(finish + 1)..]
          changed = true
          next
        end
      end
      i += 1
    end
  end
  result
end

Dir.glob(File.join(ROOT, "{lib,spec}/**/*.rb")).sort.each do |path|
  original = File.read(path)
  updated = strip_optional_parens(original)
  next if updated == original

  File.write(path, updated)
  puts path
end
