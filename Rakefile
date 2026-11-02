# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

require "rubocop/rake_task"

RuboCop::RakeTask.new

Dir.glob("tasks/*.rake").sort.each { |r| load r }

desc "The gate: tests, lint, design-doc tripwires."
task check: %i[spec rubocop design_tripwires]

namespace :release do
  # Release-only metadata guards, kept out of `check`: during development Typemap::VERSION still
  # names the last release and its CHANGELOG section isn't written yet.
  desc "Verify Typemap::VERSION has a dated CHANGELOG section and isn't already tagged."
  task :guard_version do
    version = Bundler::GemHelper.gemspec.version.to_s
    tag = "v#{version}"

    # A dated '## [x.y.z] - YYYY-MM-DD' heading: the \d date both proves the section exists and
    # rejects the literal YYYY-MM-DD placeholder.
    unless File.read("CHANGELOG.md").match?(/^## \[#{Regexp.escape(version)}\] - \d{4}-\d{2}-\d{2}/)
      abort "CHANGELOG.md has no dated '## [#{version}] - YYYY-MM-DD' section. " \
            "Move the Unreleased entries under a dated heading for #{version} first."
    end

    # Pre-empts bundler's already_tagged? path, which would silently skip tagging and then fail
    # late on a duplicate `gem push`.
    if system("git", "rev-parse", "-q", "--verify", "refs/tags/#{tag}", out: File::NULL, err: File::NULL)
      abort "Tag #{tag} already exists — #{version} has been released. Bump Typemap::VERSION first."
    end
  end
end

# Gate `rake release`: guard_clean is the first release-only sub-task (build runs before it, but
# pkg/ is disposable), so the cheap metadata guard and then the whole gate run before any tag or
# push. See design/releasing.md.
task "release:guard_clean" => %w[release:guard_version check]

task default: :check
