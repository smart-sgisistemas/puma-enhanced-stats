#!/usr/bin/env ruby
# frozen_string_literal: true

ROOT = File.expand_path("..", __dir__)
PATHS = Dir.glob(File.join(ROOT, "{lib/puma/enhanced/stats/cli/**/*.rb,spec/cli/**/*_spec.rb}")).sort

REPAIRS = [
  # precedence / nesting
  [/top_border title_label title, badge, chars/, "top_border title_label(title, badge), chars"],
  [/inner\.ljust inner_width - 1/, "inner.ljust(inner_width - 1)"],
  [/\.ljust inner\b/, ".ljust(inner)"],
  [/Time\.iso8601 worker\["synced_at"\]\.to_s \+ 0/, 'Time.iso8601(worker["synced_at"].to_s + 0)'],
  [/worker\.dig "requests", "items" \|\| \[\]/, 'worker.dig("requests", "items") || []'],
  [/worker\.dig "requests", "meta" \|\| \{\}/, 'worker.dig("requests", "meta") || {}'],
  [/worker\.dig "requests", "items"&\.size/, 'worker.dig("requests", "items")&.size'],
  [/w\.dig "requests", "items"&\.any\?/, 'w.dig("requests", "items")&.any?'],

  # missing closing parens (strip damage)
  [/AlertLevel\.for_ratio\(ratio, backlog: backlog\n/, "AlertLevel.for_ratio(ratio, backlog: backlog)\n"],
  [/LEVELS\.fetch\(level\n/, "LEVELS.fetch(level)\n"],
  [/Format\.elapsed\(collected_at, item\["started_at"\]\n/, 'Format.elapsed(collected_at, item["started_at"])' + "\n"],
  [/RESERVED\.include\? key \|\| PRIMARY\.include\?\(key\n/, "RESERVED.include?(key) || PRIMARY.include?(key)\n"],
  [/HelpContent\.lines_for\(tab\n/, "HelpContent.lines_for(tab)\n"],
  [/AlertLevel\.for_dropped summary\["requests_dropped_total"\]\)/, 'AlertLevel.for_dropped(summary["requests_dropped_total"])'],
  [/pids\.join\(", "\n/, 'pids.join(", ")' + "\n"],
  [/Entry\.new\(state_path: state_path, control_url: control_url, token: token, master_pid: master_pid\n/, "Entry.new(state_path: state_path, control_url: control_url, token: token, master_pid: master_pid)\n"],
  [/Puma::Configuration\.new\(config_files: \[@overrides\[:config_path\]\]\n/, "Puma::Configuration.new(config_files: [@overrides[:config_path]])\n"],
  [/CPU\.new\(usr: usr_pct, sys: sys_pct, idle: idle_pct, usage: usage \/ 100\.0\n/, "CPU.new(usr: usr_pct, sys: sys_pct, idle: idle_pct, usage: usage / 100.0)\n"],
  [/Usage\.new\(used: used, total: total, ratio: ratio\n/, "Usage.new(used: used, total: total, ratio: ratio)\n"],
  [/Usage\.new\(used: used, total: total, ratio: used\.to_f \/ total\n/, "Usage.new(used: used, total: total, ratio: used.to_f / total)\n"],
  [/Usage\.new\(used: 0, total: 0, ratio: 0\.0\n/, "Usage.new(used: 0, total: 0, ratio: 0.0)\n"],
  [/Result\.new\(layout: requested, saved_layout: requested, hint: nil\n/, "Result.new(layout: requested, saved_layout: requested, hint: nil)\n"],
  [/hint: "layout: stacked  saved #\{requested\}, need #\{min_cols\} cols\)"\n\s+\n/m,
   "hint: \"layout: stacked  saved \#{requested}, need \#{min_cols} cols)\"\n                )\n"],
  [/MODES\.fetch requested, 0/, "MODES.fetch(requested, 0)"],
  [/\.round 1/, ".round(1)"],
  [/\.first limit/, ".first(limit)"],

  # hash-value method calls need parens
  [/summary_value: summary_label host_cpu, puma_rss, host_mem_total,/, "summary_value: summary_label(host_cpu, puma_rss, host_mem_total),"],
  [/cpu_suffix: top_suffix host, level, cpu_gap, :cpu,/, "cpu_suffix: top_suffix(host, level, cpu_gap, :cpu),"],
  [/mem_suffix: top_suffix host, level, mem_gap_ratio, :mem,/, "mem_suffix: top_suffix(host, level, mem_gap_ratio, :mem),"],
  [/suffix: format "%3\.0f%%", ratio \* 100,/, 'suffix: format("%3.0f%%", ratio * 100),'],
  [/now: Time\.iso8601\(worker\["synced_at"\]\.to_s \+ 0\)/, 'now: Time.iso8601(worker["synced_at"].to_s + 0)'],

  # ternary method calls
  [/\? run_watch payload : run_once payload/, "? run_watch(payload) : run_once(payload)"],
  [/\? AlertLevel\.for_backlog num : AlertLevel\.for_ratio ratio/, "? AlertLevel.for_backlog(num) : AlertLevel.for_ratio(ratio)"],

  # keyword .new / Struct.new
  [/Struct\.new :(\w+(?:, :\w+)*), keyword_init: true/, 'Struct.new(:\1, keyword_init: true)'],
  [/MetricLine\.new label:/, "MetricLine.new(label:"],
  [/LabelLine\.new label:/, "LabelLine.new(label:"],
  [/Fetcher\.new overrides:/, "Fetcher.new(overrides:"],
  [/LayoutBudget\.new rows, cols, @options, worker_count:/, "LayoutBudget.new(rows, cols, @options, worker_count:"],
  [/Entry\.new control_url:/, "Entry.new(control_url:"],
  [/ScreenManager\.new options\)/, "ScreenManager.new(options))"],
  [/ScreenManager\.new options/, "ScreenManager.new(options)"],
  [/described_class\.load path\)/, "described_class.load(path))"],

  # chained .new().method — keyword args on method need parens
  [/Box\.new\(budget\.cols\)\.draw title:/, "Box.new(budget.cols).draw(title:"],
  [/Box\.new\(budget\.worker_inner_width\)\.draw_with_divider\(/, "Box.new(budget.worker_inner_width).draw_with_divider("],

  # filter_screen ternary join
  [/\.join\(", "\)/, '.join(", ")'],
  [/: \(options\.filters\.map \{ \|k, v\| "#\{k\}=#\{v\}" \}\.join\(", "\)/,
   ': (options.filters.map { |k, v| "#{k}=#{v}" }.join(", "))'],

  # spec merge damage
  [/\.merge "([^"]+)" =>/, '.merge("\1" =>'],
  [/\.merge "([^"]+)" => ([^,]+), \{\}, meta\)/, '.merge("\1" => \2, {}, meta))'],
  [/payload\.merge "workers" => \[\], \{\},/, 'payload.merge("workers" => [], {},'],
].freeze

PATHS.each do |path|
  original = File.read(path)
  updated = original.dup
  REPAIRS.each do |pattern, replacement|
    updated.gsub!(pattern, replacement)
  end
  next if updated == original

  File.write(path, updated)
  puts path
end
