# frozen_string_literal: true

require_relative "lib/confect/version"

Gem::Specification.new do |spec|
  spec.name = "confect"
  spec.version = Confect::VERSION
  spec.authors = ["Martin Vysny"]
  spec.email = ["martin@vysny.me"]

  spec.summary = "Loads a config file into a Ruby class you already wrote, checking every value."
  spec.description = <<~DESC
    Confect maps a parsed TOML, JSON or YAML file onto an ordinary Ruby class — a Data class or
    a plain class with accessors — and back, with strict types from `constrain` lines or RBS
    signatures, and without the file ever naming a class. To confect is to prepare something
    from raw ingredients: a raw file in, a checked Ruby object served out.
  DESC
  spec.homepage = "https://github.com/mvysny/confect"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Contributor-only material stays out: `design/` is the lazy doc layer, read on GitHub, and
  # AGENTS.md / CLAUDE.md are the agent files.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        %w[Gemfile Gemfile.lock Rakefile .gitignore .rspec .rubocop.yml .yardopts AGENTS.md CLAUDE.md].include?(f) ||
        f.start_with?(*%w[spec/ design/ tasks/ .github/])
    end
  end
  spec.require_paths = ["lib"]

  # No runtime dependencies, by promise (AGENTS.md): tomlrb, psych, json and rbs are the app's,
  # required where first used.
end
