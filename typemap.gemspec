# frozen_string_literal: true

require_relative "lib/typemap/version"

Gem::Specification.new do |spec|
  spec.name = "typemap"
  spec.version = Typemap::VERSION
  spec.authors = ["Martin Vysny"]
  spec.email = ["martin@vysny.me"]

  spec.summary = "Maps a Hash onto a Ruby class you already wrote, and back, checking every value."
  spec.description = <<~DESC
    Typemap maps a Hash — a parsed TOML, JSON or YAML file — onto an ordinary Ruby class, a Data
    class or a plain class with accessors, and back, with strict types from `constrain` lines or
    RBS signatures, and without the data ever naming a class. It does the mapping and nothing
    else: reading files and finding them stay with the app.
  DESC
  spec.homepage = "https://github.com/mvysny/typemap"
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

  # No runtime dependencies, by promise (AGENTS.md): rbs is the app's, required only by
  # Typemap::Mapper::RBSTypes.
end
