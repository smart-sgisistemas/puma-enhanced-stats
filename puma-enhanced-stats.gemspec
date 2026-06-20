# frozen_string_literal: true

require_relative "lib/puma/enhanced/stats/version"

Gem::Specification.new do |spec|
  spec.name = "puma-enhanced-stats"
  spec.version = Puma::Enhanced::Stats::VERSION
  spec.authors = ["Ederson José Fuzinato"]
  spec.email = ["ederson.fuzinato@sgisistemas.com.br"]

  spec.summary = "In-flight request and worker metrics for Puma via the control app."
  spec.description = "Tracks in-flight HTTP requests per Puma worker and exposes them with " \
                     "thread-pool and process metrics through GET /enhanced-stats and " \
                     "pumactl enhanced-stats on Rails 7+ applications."
  spec.homepage = "https://github.com/smart-sgisistemas/puma-enhanced-stats"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "#{spec.homepage}/blob/main/docs/README.md"

  spec.files = Dir.chdir(__dir__) do
    tracked = `git ls-files -z 2>/dev/null`.split("\x0").reject(&:empty?)
    files = if tracked.empty?
              Dir.glob("{lib,schema,docs}/**/*").select { |f| File.file?(f) } +
                %w[README.md LICENSE.txt CHANGELOG.md]
            else
              tracked
            end
    files.reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github .idea/ appveyor Gemfile])
    end
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "puma", ">= 8.0", "< 9"
  spec.add_dependency "rails", ">= 7.0", "< 8"

  spec.add_development_dependency "json_schemer", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "simplecov", "~> 0.22"
  spec.add_development_dependency "yard", "~> 0.9"
  spec.add_development_dependency "rbs", ">= 3.0"
end
