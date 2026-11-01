# frozen_string_literal: true

require_relative "typemap/version"
require_relative "typemap/error"
require_relative "typemap/constrain"
require_relative "typemap/mapper"

# Maps a Hash onto a Ruby class you already wrote, and back, checking every value on the way.
# {Typemap::Mapper} does the mapping; {Typemap::Constrain} is what a class extends to give its
# properties types and limits.
module Typemap
end
