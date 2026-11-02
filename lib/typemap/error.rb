# frozen_string_literal: true

module Typemap
  # The root of Typemap's own errors; rescue it to catch both kinds below.
  class Error < StandardError
  end

  # The data does not fit the class: a value of the wrong type or outside its limits, an unknown
  # key, a required key missing, a failed `validate`. The file's author fixes it; the message starts
  # with the path of the offending value and, for a classic mistake whose fix is mechanical, ends
  # with the fix:
  #
  #   ballooning.raise_at_percent: expected Integer, got "70"; remove the quotes
  #   server: expected Array[Server], got a single Server; wrap it in an array
  #   ui.sandbox: unknown key; sandbox belongs to the top level
  #
  # An array entry whose class names it with `entry_name` shows that after its index,
  # `server[1] "grok".url`.
  #
  # A type is named as RBS spells it, a class without its namespace on load (`Server`, not
  # `Shared::Config::Server`), in full on dump. Neither type nor fix uses a format's words, TOML's
  # "table" or `[[server]]` (`D_format_neutral_hints`). No line number: the parsers keep none in
  # the Hash they return, so the path stands in.
  class DataError < Error
    # @return [String] the dotted path of the offending value, `""` for the root object
    attr_reader :path

    # @return [String] what is wrong with the value: the message without its path
    attr_reader :detail

    # @param path [String] the dotted path of the offending value, `""` for the root
    # @param detail [String] what is wrong with it
    def initialize(path, detail)
      @path = path
      @detail = detail
      super(path.empty? ? detail : "#{path}: #{detail}")
    end
  end

  # The class cannot be mapped: a property with no type, a type declared twice, a default the
  # type rejects, a class `new` cannot build bare. The class's author fixes it; it is raised
  # when the mapper first reads the class, whatever the file holds.
  class DefinitionError < Error
  end
end
