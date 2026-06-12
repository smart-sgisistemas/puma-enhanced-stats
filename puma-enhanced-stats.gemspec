# frozen_string_literal: true

require_relative "lib/puma/enhanced/stats/version"

Gem::Specification.new do |spec|
  spec.name = "puma-enhanced-stats"
  spec.version = Puma::Enhanced::Stats::VERSION
  spec.authors = ["Ederson José Fuzinato"]
  spec.email = ["ederson.fuzinato@sgisistemas.com.br"]

  spec.summary = "Enhanced statistics for Puma web server."
  spec.description = "Gem to collect, enrich, and expose extended statistics from Puma's control_app."
  spec.homepage = "https://github.com/smart-sgisistemas/puma-enhanced-stats"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = "https://github.com/smart-sgisistemas/puma-enhanced-stats"
  spec.metadata["source_code_uri"] = "https://github.com/smart-sgisistemas/puma-enhanced-stats"
  spec.metadata["changelog_uri"] = "https://github.com/smart-sgisistemas/puma-enhanced-stats/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github .idea/ appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
end
