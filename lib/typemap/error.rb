# frozen_string_literal: true

module Typemap
  # The root of Typemap's own errors; rescue it to catch both kinds below.
  class Error < StandardError
  end

  # The data does not fit the class: a value of the wrong type or outside its limits, an unknown
  # key, a failed `validate`. The file's author fixes it; the message starts with the path of
  # the offending value, `ballooning.raise_at_percent: expected Integer, got "70"`.
  class DataError < Error
    # @return [String] the dotted path of the offending value, `""` for the root object
    attr_reader :path

    # @param path [String] the dotted path of the offending value, `""` for the root
    # @param detail [String] what is wrong with it
    def initialize(path, detail)
      @path = path
      super(path.empty? ? detail : "#{path}: #{detail}")
    end
  end

  # The class cannot be mapped: a property with no type, a type declared twice, a default the
  # type rejects, a class `new` cannot build bare. The class's author fixes it; it is raised
  # when the mapper first reads the class, whatever the file holds.
  class DefinitionError < Error
  end
end
