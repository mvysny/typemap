# frozen_string_literal: true

module Typemap
  class Mapper
    # How a load error words the found value and the fix, for the source the app names in
    # `load(..., source:)`. The types detect the mistake in the Hash; a wording only spells it:
    #
    #   :ruby  server: expected Array[Server], got a single Server; wrap it in an array
    #   :toml  server: expected Array[Server], got a single Server; write [[server]], not [server], or server = [{…}]
    #
    # Each source is a module answering the same six calls: `found(value)`, `wrap(path, entry)`,
    # `unwrap(path)`, `quote(value)`, `unquote` and `misplaced(key, path, owner)`. A hint returns
    # `nil` for none. A dump error is worded for {Ruby}: its reader is the programmer.
    #
    # @api private
    module Wording
      # @param source [Symbol] `:ruby`, `:toml`, `:json` or `:yaml`
      # @return [Module] the wording for it
      # @raise [ArgumentError] on any other source
      def self.for(source)
        case source
        when :ruby then Ruby
        when :toml then TOML
        when :json then JSON
        when :yaml then YAML
        else raise ArgumentError, "source: must be :ruby, :toml, :json or :yaml, got #{source.inspect}"
        end
      end

      # @param value [Object]
      # @return [String] its `inspect`, cut at 60 characters
      def self.inspected(value)
        text = value.inspect
        text.length > 61 ? "#{text[0, 60]}…" : text
      end

      # @param key [String]
      # @param owner [String] the enclosing object's path, `""` for the top level
      # @return [String] `sandbox belongs to the top level`
      def self.belongs(key, owner) = "#{key} belongs to #{owner.empty? ? "the top level" : owner}"

      QUOTE = "quote it to make it a string"
      UNQUOTE = "remove the quotes"

      # A Hash built in Ruby: the found value's class names the mistake, and there are no quotes
      # to add or remove.
      #
      #   value: expected String, got Integer 70
      module Ruby
        # @param value [Object]
        # @return [String] `Integer 70`; bare for `nil`, `true`, `false` and an inspect that names
        #   its class already, `#<data Server …>`
        def self.found(value)
          text = Wording.inspected(value)
          [nil, true, false].include?(value) || text.start_with?("#<") ? text : "#{value.class} #{text}"
        end

        # @param _path [String]
        # @param _entry [Boolean]
        # @return [String]
        def self.wrap(_path, _entry) = "wrap it in an array"

        # @param _path [String]
        # @return [String]
        def self.unwrap(_path) = "unwrap it"

        # @param _value [Object]
        # @return [nil]
        def self.quote(_value) = nil

        # @return [nil]
        def self.unquote = nil

        # @param key [String]
        # @param _path [String]
        # @param owner [String]
        # @return [String]
        def self.misplaced(key, _path, owner) = Wording.belongs(key, owner)
      end

      # TOML: headers spelled from the path, `llm[0].servers` → `[[llm.servers]]`, since a header
      # names no index.
      #
      # == Implementation details
      #
      # An array hint names the inline spelling too, `server = [{…}]`: Typemap can't tell which
      # one the file used.
      module TOML
        # @param value [Object]
        # @return [String]
        def self.found(value) = Wording.inspected(value)

        # @param path [String]
        # @param entry [Boolean] whether the lone value is an object
        # @return [String]
        def self.wrap(path, entry)
          return "wrap it in [ ]" unless entry && keyed?(path)

          "write #{header(path, array: true)}, not #{header(path)}, or #{key(path)} = [{…}]"
        end

        # @param path [String]
        # @return [String]
        def self.unwrap(path)
          return "remove the [ ]" unless keyed?(path)

          "write #{header(path)}, not #{header(path, array: true)}, or #{key(path)} = {…}"
        end

        # @param _value [Object]
        # @return [String]
        def self.quote(_value) = QUOTE

        # @return [String]
        def self.unquote = UNQUOTE

        # @param key [String]
        # @param path [String] the object the key sits in
        # @param owner [String] the enclosing object that has the key, `""` for the top level
        # @return [String] `sandbox belongs to code, under [code] before [code.panel]`
        def self.misplaced(key, path, owner)
          where = owner.empty? ? "before any [header]" : "under #{header(owner)} before #{header(path)}"
          "#{Wording.belongs(key, owner)}, #{where}"
        end

        # @param path [String] `llm[0].params`
        # @param array [Boolean] whether to spell it as an array entry's header
        # @return [String] `[llm.params]`; `[[llm]]` for `llm[0]`
        def self.header(path, array: path.end_with?("]"))
          name = path.split(".").map { |key| bare(key.sub(/\[\d+\]\z/, "")) }.join(".")
          array ? "[[#{name}]]" : "[#{name}]"
        end

        # @param path [String]
        # @return [Boolean] whether the value sits under a key, which a header can name — not at the
        #   root, nor directly in an array
        def self.keyed?(path) = !path.empty? && !path.end_with?("]")

        # @param path [String] `llm[0].servers`
        # @return [String] `servers`, as TOML writes it
        def self.key(path) = bare(path.split(".").last)

        # @param key [String]
        # @return [String] the key as TOML writes it, quoted unless bare
        def self.bare(key) = key.match?(/\A[A-Za-z0-9_-]+\z/) ? key : key.inspect
        private_class_method :header, :keyed?, :key, :bare
      end

      # JSON: brackets and braces.
      module JSON
        # @param value [Object]
        # @return [String]
        def self.found(value) = Wording.inspected(value)

        # @param _path [String]
        # @param _entry [Boolean]
        # @return [String]
        def self.wrap(_path, _entry) = "wrap it in [ ]"

        # @param _path [String]
        # @return [String]
        def self.unwrap(_path) = "remove the [ ]"

        # @param _value [Object]
        # @return [String]
        def self.quote(_value) = QUOTE

        # @return [String]
        def self.unquote = UNQUOTE

        # @param key [String]
        # @param path [String] the object the key sits in
        # @param owner [String] the enclosing object that has the key, `""` for the top level
        # @return [String] `sandbox belongs to the top level; move it out of pane's { }`
        def self.misplaced(key, path, owner) = "#{Wording.belongs(key, owner)}; move it out of #{path}'s { }"
      end

      # YAML in block style: `- ` and indentation.
      module YAML
        # @param value [Object]
        # @return [String]
        def self.found(value) = Wording.inspected(value)

        # @param _path [String]
        # @param _entry [Boolean]
        # @return [String]
        def self.wrap(_path, _entry) = 'put "- " before it'

        # @param _path [String]
        # @return [String]
        def self.unwrap(_path) = 'remove the "- "'

        # Psych reads YAML 1.1, so `no` loads as `false`: the Norway problem.
        #
        # @param value [Object]
        # @return [String]
        def self.quote(value)
          [true, false].include?(value) ? "#{QUOTE}; YAML reads yes, no, on and off as booleans" : QUOTE
        end

        # @return [String]
        def self.unquote = UNQUOTE

        # @param key [String]
        # @param _path [String]
        # @param owner [String]
        # @return [String] `sandbox belongs to the top level; dedent it`
        def self.misplaced(key, _path, owner) = "#{Wording.belongs(key, owner)}; dedent it"
      end
    end
  end
end
