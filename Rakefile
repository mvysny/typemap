# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

require "rubocop/rake_task"

RuboCop::RakeTask.new

Dir.glob("tasks/*.rake").sort.each { |r| load r }

desc "The gate: tests, lint, design-doc tripwires."
task check: %i[spec rubocop design_tripwires]

task default: :check
