# frozen_string_literal: true

require "fileutils"
require "puma/enhanced/stats/cli/options"
require "puma/enhanced/stats/cli/user_config"

RSpec.describe Puma::Enhanced::Stats::CLI::UserConfig do
  let(:tmpdir) { Dir.mktmpdir "puma-enhanced-stats-pesrc-" }
  let(:path) { File.join tmpdir, ".pesrc" }

  after do
    FileUtils.remove_entry tmpdir
  end

  def write_config(contents)
    File.write path, contents
  end

  it "loads key=value pairs and ignores comments and blank lines" do
    write_config <<~RC
      # layout
      frame_layout=grid

      request_display=stack
    RC

    expect(described_class.load(path)).to eq(
      "frame_layout" => "grid",
      "request_display" => "stack"
    )
  end

  it "returns an empty hash for a missing file" do
    expect(described_class.load(File.join(tmpdir, "missing"))).to eq({})
  end

  it "applies preferences to options" do
    write_config <<~RC
      frame_layout=split
      request_display=inline
      show_top=false
      show_outsiders=true
      sort.process=cpu
      sort.field=path_info
      sort.dir=asc
      focus_worker=2
      filter.method=GET
    RC

    options = described_class.apply!(described_class::Options.new, described_class.load(path))

    expect(options.frame_layout).to eq "split"
    expect(options.request_display).to eq "inline"
    expect(options.top?).to be false
    expect(options.show_outsiders?).to be true
    expect(options.sort_process).to eq "cpu"
    expect(options.sort_field).to eq "path_info"
    expect(options.sort_dir).to eq "asc"
    expect(options.focus_worker).to eq 2
    expect(options.filters).to eq("method" => "GET")
  end

  it "serializes and saves options" do
    options = Puma::Enhanced::Stats::CLI::Options.new
    options.frame_layout = "grid"
    options.request_display = "stack"
    options.show_top = false
    options.show_outsiders = true
    options.sort_process = "rss"
    options.filters["method"] = "POST"
    options.focus_worker = 1

    described_class.save! options, path

    expect(File.read(path)).to eq(described_class.serialize(options))
    expect(described_class.load(path)["frame_layout"]).to eq("grid")
    expect(described_class.load(path)["filter.method"]).to eq("POST")
  end
end
