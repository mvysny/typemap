# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in confect.gemspec
gemspec

gem "irb"
gem "rake", "~> 13.2"

group :test do
  gem "minitest", "~> 6.0"
  gem "rbs", "~> 4.2" # Confect::Mapper::RBSTypes; the app's dependency, never the gem's
  gem "rspec-core", "~> 3.13"
  gem "simplecov", "~> 0.22", require: false
end

group :development do
  gem "redcarpet", "~> 3.6" # Markdown formatting for YARD
  gem "rubocop", "~> 1.21"
  gem "yard", "~> 0.9.37"
end
