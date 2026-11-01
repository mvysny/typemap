# frozen_string_literal: true

require_relative "confect/version"

# Loads a config file into a Ruby class you already wrote, checking every value on the way.
# The mapper (`Confect::Mapper`) is the core; the top-level namespace is kept free for the
# higher-level loading that finds an app's config and state files.
module Confect
end
