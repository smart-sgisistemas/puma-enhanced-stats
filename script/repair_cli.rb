#!/usr/bin/env ruby
# frozen_string_literal: true

ROOT = File.expand_path("..", __dir__)

REPAIRS = [
  [/Struct\.new\s*\n(\s+):/, "Struct.new(\n\\1:"],
  [/Struct\.new\s*\n(\s+):puma_cpu/, "Struct.new(\n\\1:puma_cpu"],
  [/Result\.new\s*\n(\s+)puma_cpu:/, "Result.new(\n\\1puma_cpu:"],
  [/SyncFreshness\.evaluate\s*\n/, "SyncFreshness.evaluate(\n"],
  [/ResourceAttribution\.compute\s*\n/, "ResourceAttribution.compute(\n"],
  [/TopRenderer\.new\s*\n/, "TopRenderer.new(\n"],
  [/LayoutRegistry\.resolve\s*\n/, "LayoutRegistry.resolve(\n"],
  [/LayoutBudget\.new\s*\n/, "LayoutBudget.new(\n"],
  [/FrameRenderer\.new\([^)]+\)\.render\s*\n/, nil], # keep
  [/CPU\.new\s+usr:/, "CPU.new(usr:"],
  [/Usage\.new\s+used:/, "Usage.new(used:"],
  [/MetricLine\.new\s+label:/, "MetricLine.new(label:"],
  [/LabelLine\.new\s+label:/, "LabelLine.new(label:"],
  [/Entry\.new\s+state_path:/, "Entry.new(state_path:"],
  [/Entry\.new\s+control_url:/, "Entry.new(control_url:"],
  [/Result\.new\s+layout:/, "Result.new(layout:"],
  [/Fetcher\.new\s+overrides:/, "Fetcher.new(overrides:"],
  [/Puma::Configuration\.new\s+config_files:/, "Puma::Configuration.new(config_files:"],
  [/new\s+build\s+host:/, "new(build(host:"],
  [/summary_label\s+host_cpu/, "summary_label(host_cpu"],
  [/top_cpu_suffix\s+host/, "top_cpu_suffix(host"],
  [/top_mem_suffix\s+host/, "top_mem_suffix(host"],
  [/AlertLevel\.for_dropped\s+summary/, "AlertLevel.for_dropped(summary"],
  [/Format\.rel_time\s+worker/, "Format.rel_time(worker"],
  [/AlertLevel\.for_backlog\s+num/, "AlertLevel.for_backlog(num"],
  [/AlertLevel\.for_ratio\s+ratio/, "AlertLevel.for_ratio(ratio"],
  [/LEVELS\.fetch\s+level/, "LEVELS.fetch(level"],
  [/HelpContent\.lines_for\s+tab/, "HelpContent.lines_for(tab"],
  [/PRIMARY\.include\?\s+key/, "PRIMARY.include?(key"],
  [/Format\.elapsed\s+collected_at/, "Format.elapsed(collected_at"],
  [/run_watch\s+payload/, "run_watch(payload"],
  [/run_once\s+payload/, "run_once(payload"],
  [/\.join\s+",\s*"/, '.join(", "'],
  [/field\.split\s+"\.",\s*2\.last/, 'field.split(".", 2).last'],
  [/compute\s+host:/, "compute(host:"],
  [/\.render\s+max_items:/, ".render(max_items:"],
  [/worker_title_badge\s+puma/, "worker_title_badge(puma"],
  [/worker_metrics\s+puma/, "worker_metrics(puma"],
  [/process_rows\s+workers/, "process_rows(workers"],
  [/sort_rows\s+rows/, "sort_rows(rows"],
  [/sort_workers\s+workers/, "sort_workers(workers"],
  [/sort_process_rows\s+rows/, "sort_process_rows(rows"],
  [/sum_cpu\s+process_by_pid/, "sum_cpu(process_by_pid"],
  [/sum_rss\s+process_by_pid/, "sum_rss(process_by_pid"],
  [/parse\s+argv/, "parse(argv"], # user may want without - keep for repair validity
  [/UserConfig\.apply!\s+options/, "UserConfig.apply!(options"],
  [/argv\.include\?\s+"--no-rc"/, 'argv.include?("--no-rc")'],
  [/ScreenManager\.new\s+@options/, "ScreenManager.new(@options"],
  [/ScreenManager\.new\s+options/, "ScreenManager.new(options"],
  [/described_class\.load\s+path/, "described_class.load(path"],
  [/payload\.merge\s+"workers"/, 'payload.merge("workers"'],
  [/CPU\.new\s+usr:/, "CPU.new(usr:"],
].freeze

def close_multiline_calls(code)
  lines = code.lines
  out = []
  i = 0
  while i < lines.length
    line = lines[i]
    if line =~ /(SyncFreshness\.evaluate|ResourceAttribution\.compute|Result\.new|TopRenderer\.new|LayoutBudget\.new|LayoutRegistry\.resolve|FrameRenderer\.new\([^)]+\)\.render|ResourceAttribution\.compute|classify_level)\($/
      out << line
      i += 1
      while i < lines.length
        out << lines[i]
        if lines[i] =~ /^\s*\)\s*$/
          break
        end
        if lines[i] =~ /^\s*\)\s*$/ || (lines[i] !~ /:\s/ && lines[i].strip.empty?)
          # continue
        end
        if lines[i] =~ /^\s*$/ && out.last&.include?("degraded: false")
          out << "              )\n" unless out.any? { |l| l.strip == ")" }
        end
        i += 1
        break if out.last&.strip == ")" || (lines[i - 1] =~ /degraded: false/ && !out.last.include?(")"))
      end
      out << "              )\n" if line.include?("Result.new") && !out.join.include?("degraded: false)\n")
    else
      out << line
      i += 1
    end
  end
  out.join
end

Dir.glob(File.join(ROOT, "lib/puma/enhanced/stats/cli/**/*.rb")).sort.each do |path|
  original = File.read(path)
  updated = original.dup
  REPAIRS.each do |pattern, replacement|
    next unless replacement

    updated.gsub!(pattern, replacement)
  end

  # Close unclosed multiline keyword arg blocks
  updated.gsub!(
    /(SyncFreshness\.evaluate\(\n(?:.+\n)+?)(\n\s*title =)/m,
    "\\1            )\n\\2"
  )
  updated.gsub!(
    /(Result\.new\(\n(?:.+\n)+?)(\n\s*end)/m,
    "\\1              )\n\\2"
  )
  updated.gsub!(
    /(ResourceAttribution\.compute\(\n\s+host:.+\n\s+process_by_pid:.+\n\s+degraded:.+\n)(\s+end)/m,
    "\\1            )\n\\2"
  )
  updated.gsub!(
    /Struct\.new\(\n(\s+:.+\n)+\s+keyword_init: true\n\s+\n/m,
    "Struct.new(\n\\1            keyword_init: true\n          )\n"
  )

  next if updated == original

  File.write(path, updated)
  puts path
end
