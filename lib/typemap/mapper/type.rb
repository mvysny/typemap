# frozen_string_literal: true

module Typemap
  class Mapper
    # The types the mapper checks a value against — the small subset of RBS it supports, whether
    # the type came from `constrain type:` or from `sig/*.rbs` (`D_types_declared`). Each type
    # answers five questions:
    #
    # - `load(value, path, session, base)` — the value as the property holds it, or a
    #   {DataError}; strict, never coerced, a whole number between Integer and Float aside;
    # - `dump(value, mapper, path)` — the value as plain Hash/Array/scalar data;
    # - `each_object(value, mapper, path) { |object, path| }` — the app's objects inside a value
    #   that has passed `load` or `dump`, for the validation that walks the result;
    # - `accepts?(value)` — whether a default fits;
    # - `limits` — which of `constrain`'s `in:` / `format:` / `not_blank:` / `not_empty:` the type
    #   can take.
    #
    # `to_s` is the RBS spelling, used in every message; `to_s(short: true)` drops each class's
    # namespace, for load messages, whose reader writes the file and never sees the code.
    #
    # @api private
    module Type
      # `expected Integer, got "70"; remove the quotes`.
      #
      # @param type [#to_s] the expected type
      # @param value [Object] what was found instead
      # @param path [String]
      # @param wording [Module] spells the found value: the load's {Wording}, {Wording::Ruby} on dump
      # @param found [String, nil] words for the found value, in place of the wording's
      # @param hint [String, nil] the fix, for a mistake whose fix is mechanical
      # @raise [DataError] always
      def self.mismatch(type, value, path, wording: Wording::Ruby, found: nil, hint: nil)
        detail = "expected #{type}, got #{found || wording.found(value)}"
        raise DataError.new(path, hint ? "#{detail}; #{hint}" : detail)
      end

      # @param klass [Class]
      # @return [String] `Server` for `Shared::Config::Server`
      def self.short_name(klass)
        klass.name&.split("::")&.last || klass.inspect
      end

      # Whether the block loads without an error, for a hint on a value that has already failed;
      # the loaded value is dropped.
      #
      # @yieldreturn [Object] the value loaded
      # @return [Boolean]
      def self.loads?
        yield
        true
      rescue Error
        false
      end

      # Whether a file wrote the value unquoted where a String belongs — a number, a bool, a
      # parser's date-time: YAML's `no` is `false`, `1.10` is the Float `1.1`.
      #
      # @param value [Object]
      # @return [Boolean]
      def self.unquoted?(value)
        !value.nil? && [String, Symbol, Array, Hash].none? { |klass| value.is_a?(klass) }
      end

      # A String a number's quotes were put around, `"70"`. Not what `Integer()` takes: `"0x1A"`
      # and `"1_000"` may not have been meant as numbers.
      NUMBER_TEXT = { Integer => /\A[+-]?\d+\z/, Float => /\A[+-]?\d+(\.\d+)?([eE][+-]?\d+)?\z/ }.freeze

      # @param path [String]
      # @param key [String, Symbol]
      # @return [String] the path of `key` under `path`
      def self.child(path, key)
        path.empty? ? key.to_s : "#{path}.#{key}"
      end

      # `Integer`, `Float` or `String`: the value must be an instance. On load alone a whole number
      # crosses between the two numeric classes, exactly or not at all — `5` loads as `5.0`, `5.0`
      # as `5`, `5.1` raises (`D_whole_numbers`); a default and a dumped value stay strict.
      #
      # @!attribute [r] klass
      #   @return [Class] `Integer`, `Float` or `String`
      Scalar = Data.define(:klass) do
        def load(value, path, session, _base)
          return value if value.is_a?(klass)

          whole = Type.whole_number(value, klass)
          return whole unless whole.nil?

          wording = session.wording
          hint = if klass == String
                   wording.quote(value) if Type.unquoted?(value)
                 elsif value.is_a?(String) && Type::NUMBER_TEXT.fetch(klass).match?(value)
                   wording.unquote
                 end
          Type.mismatch(self, value, path, wording: wording, hint: hint)
        end

        def dump(value, _mapper, path) = (value.is_a?(klass) ? value : Type.mismatch(self, value, path))
        def each_object(_value, _mapper, _path) = nil
        def accepts?(value) = value.is_a?(klass)
        def limits = klass == String ? %i[in format not_blank] : %i[in]
        def numeric? = klass != String
        def nested_classes = []
        def to_s(**) = klass.name
      end

      # `bool`: `true` or `false`.
      Bool = Data.define do
        def load(value, path, session, _base)
          return value if accepts?(value)

          wording = session.wording
          Type.mismatch(self, value, path, wording: wording, hint: (wording.unquote if %w[true false].include?(value)))
        end

        def dump(value, _mapper, path) = (accepts?(value) ? value : Type.mismatch(self, value, path))
        def each_object(_value, _mapper, _path) = nil
        def accepts?(value) = [true, false].include?(value)
        def limits = []
        def numeric? = false
        def nested_classes = []
        def to_s(**) = "bool"
      end

      # A union of literals, `"short" | "verbose"`: the value must equal one of them, class
      # included — `1.0` is not `1`.
      #
      # @!attribute [r] values
      #   @return [Array<String, Integer, Float, Boolean>]
      Literals = Data.define(:values) do
        def load(value, path, session, _base)
          return value if accepts?(value)

          wording = session.wording
          hint = (wording.quote(value) if values.all?(String) && Type.unquoted?(value))
          Type.mismatch(self, value, path, wording: wording, hint: hint)
        end

        def dump(value, _mapper, path) = (accepts?(value) ? value : Type.mismatch(self, value, path))
        def each_object(_value, _mapper, _path) = nil
        def accepts?(value) = values.any? { |literal| literal.eql?(value) }
        def limits = []
        def numeric? = false
        def nested_classes = []
        def to_s(**) = values.map(&:inspect).join(" | ")
      end

      # `T?`: `nil`, or a `T`.
      #
      # @!attribute [r] inner
      #   @return [Object] the type of a non-nil value
      Optional = Data.define(:inner) do
        def load(value, path, session, base) = (value.nil? ? nil : inner.load(value, path, session, base))
        def dump(value, mapper, path) = (value.nil? ? nil : inner.dump(value, mapper, path))
        def each_object(value, mapper, path, &) = (inner.each_object(value, mapper, path, &) unless value.nil?)
        def accepts?(value) = value.nil? || inner.accepts?(value)
        def limits = inner.limits
        def numeric? = inner.numeric?
        def nested_classes = inner.nested_classes

        def to_s(short: false)
          inner.is_a?(Literals) && inner.values.size > 1 ? "(#{inner})?" : "#{inner.to_s(short: short)}?"
        end
      end

      # `Array[T]`: an Array whose every element is a `T`; an element's path is `key[3]`. A lone `T`
      # where the Array belongs — TOML's `[server]` for `[[server]]` — raises
      # `server: expected Array[Server], got a single Server; wrap it in an array`, the fix in the
      # load's {Wording}.
      #
      # An entry whose class has a class method `entry_name(raw)` is named in its errors after its
      # index — `server[1] "grok".url: required` — `raw` being the entry as a file would hold it:
      #
      #   def self.entry_name(raw) = raw["id"]
      #
      # == Implementation details
      #
      # The name is worked out only when an entry's error passes through, so a load that succeeds
      # never calls `entry_name`. `raw` is always plain data with String keys: on load the file's
      # Hash, on validation and dump the entry dumped by {Mapper#entry_hash}. No name, just the
      # index, when `entry_name` returns anything but a non-empty String; when it raises, a
      # warning says why, and the error the user needs is raised unnamed.
      #
      # @!attribute [r] element
      #   @return [Object] the elements' type
      ArrayOf = Data.define(:element) do
        def load(value, path, session, _base)
          single(value, path, session) unless value.is_a?(Array)
          value.each_with_index.map do |item, i|
            at = "#{path}[#{i}]"
            named(item, at, session.mapper) { element.load(item, at, session, nil) }
          end
        end

        def dump(value, mapper, path)
          Type.mismatch(self, value, path) unless value.is_a?(Array)
          value.each_with_index.map do |item, i|
            at = "#{path}[#{i}]"
            named(item, at, mapper) { element.dump(item, mapper, at) }
          end
        end

        def each_object(value, mapper, path, &)
          value.each_with_index do |item, i|
            at = "#{path}[#{i}]"
            named(item, at, mapper) { element.each_object(item, mapper, at, &) }
          end
        end

        def accepts?(value) = value.is_a?(Array) && value.all? { |item| element.accepts?(item) }
        def limits = %i[not_empty]
        def numeric? = false
        def nested_classes = element.nested_classes
        def to_s(short: false) = "Array[#{element.to_s(short: short)}]"

        private

        # @raise [DataError] always
        def single(value, path, session)
          spelled = to_s(short: true)
          wording = session.wording
          if !value.nil? && Type.loads? { element.load(value, path, session, nil) }
            Type.mismatch(spelled, value, path, found: "a single #{element.to_s(short: true)}",
                                                hint: wording.wrap(path, value.is_a?(Hash)))
          end
          Type.mismatch(spelled, value, path, wording: wording)
        end

        # @return [Object] the block's result
        # @raise [DataError] the block's, its path naming the entry when it has a name
        def named(item, at, mapper)
          yield
        rescue DataError => e
          name = entry_name(item, at, mapper)
          raise e if name.nil?

          renamed = DataError.new("#{at} #{name.inspect}#{e.path.delete_prefix(at)}", e.detail)
          renamed.set_backtrace(e.backtrace)
          raise renamed, cause: e.cause
        end

        # @return [String, nil]
        def entry_name(item, at, mapper)
          ref = element.is_a?(Optional) ? element.inner : element
          return unless ref.is_a?(ClassRef) && ref.klass.respond_to?(:entry_name)

          raw = case item
                when Hash then item.transform_keys(&:to_s)
                when ref.klass then mapper.entry_hash(item)
                end
          name = raw && ref.klass.entry_name(raw)
          name if name.is_a?(String) && !name.empty?
        rescue StandardError => e
          warn "Typemap: #{at} left unnamed, #{ref.klass}.entry_name: #{e.class}: #{e.message}"
          nil
        end
      end

      # `Hash[String, T]`: a Hash with String keys (a Symbol key is taken as its String) and a
      # `T` under each.
      #
      # @!attribute [r] value
      #   @return [Object] the values' type
      HashOf = Data.define(:value) do
        def load(raw, path, session, _base)
          Type.mismatch(to_s(short: true), raw, path, wording: session.wording) unless raw.is_a?(Hash)
          Type.string_keys(raw, path).to_h { |key, item| [key, value.load(item, Type.child(path, key), session, nil)] }
        end

        def dump(raw, mapper, path)
          Type.mismatch(self, raw, path) unless raw.is_a?(Hash)
          Type.string_keys(raw, path).to_h { |key, item| [key, value.dump(item, mapper, Type.child(path, key))] }
        end

        def each_object(raw, mapper, path, &)
          raw.each { |key, item| value.each_object(item, mapper, Type.child(path, key), &) }
        end

        def accepts?(raw) = raw.is_a?(Hash) && raw.all? { |key, item| key.is_a?(String) && value.accepts?(item) }
        def limits = %i[not_empty]
        def numeric? = false
        def nested_classes = value.nested_classes
        def to_s(short: false) = "Hash[String, #{value.to_s(short: short)}]"
      end

      # `Object`: plain data passed through as the file holds it, for a value whose meaning is
      # someone else's — `Hash[String, Object]` for extra keys sent to a server verbatim:
      #
      #   { "kwargs" => { "enable_thinking" => false, stop: nil } }    # in
      #   { "kwargs" => { "enable_thinking" => false, "stop" => nil } } # out, new containers
      #
      # Plain data is what Typemap's other types load — a String, Integer, Float, bool, Array or
      # Hash, `nil` nested inside — on load and dump alike, so a `Proc` or a TOML date-time
      # raises. Keys are Strings all the way down, a Symbol taken as its String. `nil` in its own
      # place needs `Object?`, as every type does. See `D_object_plain_data`.
      Plain = Data.define do
        def load(value, path, session, _base) = copy(value, path, session.wording)
        def dump(value, _mapper, path) = copy(value, path, Wording::Ruby)

        def each_object(_value, _mapper, _path) = nil
        def accepts?(value) = !value.nil? && Type.plain?(value)
        def limits = []
        def numeric? = false
        def nested_classes = []
        def to_s(**) = "Object"

        private

        def copy(value, path, wording)
          Type.mismatch(self, value, path, wording: wording) if value.nil?
          Type.plain(value, path, wording)
        end
      end

      # A class of the app's own — a data class or an accessor class — loaded from a Hash by
      # the mapper, recursively.
      #
      # @!attribute [r] klass
      #   @return [Class]
      ClassRef = Data.define(:klass) do
        def load(value, path, session, base) = session.load_object(klass, value, path, base)

        def dump(value, mapper, path)
          Type.mismatch(self, value, path) unless value.is_a?(klass)
          mapper.dump_object(value, path)
        end

        def each_object(value, _mapper, path) = yield(value, path)

        def accepts?(value) = value.is_a?(klass)
        def limits = []
        def numeric? = false
        def nested_classes = [klass]
        def to_s(short: false) = short ? Type.short_name(klass) : (klass.name || klass.inspect)
      end

      # A whole number as the other numeric class, when it converts exactly: `5` as a Float is
      # `5.0`, `5.0` as an Integer is `5`. Not `5.1`, NaN or infinity as an Integer, nor
      # `2**53 + 1` as a Float, which would round.
      #
      # @param value [Object]
      # @param klass [Class] the class the property declares
      # @return [Integer, Float, nil] the converted value, or nil when it does not convert exactly
      def self.whole_number(value, klass)
        if klass == Float && value.is_a?(Integer)
          float = value.to_f
          float if float.finite? && float.to_i == value
        elsif klass == Integer && value.is_a?(Float)
          value.to_i if value.finite? && value.to_i == value
        end
      end

      PLAIN_SCALARS = [String, Integer, Float, TrueClass, FalseClass, NilClass].freeze

      # A copy of plain data, every Hash's keys as Strings.
      #
      # @param value [Object]
      # @param path [String]
      # @param wording [Module] the {Wording} that spells a value no type loads
      # @return [Object] the copy
      # @raise [DataError] on a value no Typemap type loads, or a key neither String nor Symbol
      def self.plain(value, path, wording)
        case value
        when Array then value.each_with_index.map { |item, i| plain(item, "#{path}[#{i}]", wording) }
        when Hash then string_keys(value, path).to_h { |key, item| [key, plain(item, child(path, key), wording)] }
        when *PLAIN_SCALARS then value
        else mismatch("plain data (String, Integer, Float, bool, nil, Array or Hash)", value, path, wording: wording)
        end
      end

      # @param value [Object]
      # @return [Boolean] whether `value` is plain data with String keys, as a default must be
      def self.plain?(value)
        case value
        when Array then value.all? { |item| plain?(item) }
        when Hash then value.all? { |key, item| key.is_a?(String) && plain?(item) }
        else PLAIN_SCALARS.any? { |klass| value.is_a?(klass) }
        end
      end

      # A Hash's keys as Strings, a Symbol key taken as its String.
      #
      # @param hash [Hash]
      # @param path [String]
      # @return [Hash{String => Object}]
      # @raise [DataError] on a key that is neither, or on `"a"` and `:a` both present
      def self.string_keys(hash, path)
        hash.each_with_object({}) do |(key, item), out|
          raise DataError.new(path, "key #{key.inspect} is not a String") unless key.is_a?(String) || key.is_a?(Symbol)

          name = key.to_s
          raise DataError.new(path, "key #{name} given twice, as a String and as a Symbol") if out.key?(name)

          out[name] = item
        end
      end
    end
  end
end
