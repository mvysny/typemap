# frozen_string_literal: true

module Confect
  class Mapper
    # The types the mapper checks a value against — the small subset of RBS it supports, whether
    # the type came from `constrain type:` or from `sig/*.rbs` (`D_types_declared`). Each type
    # answers four questions:
    #
    # - `load(value, path, session, base)` — the value as the property holds it, or a
    #   {DataError}; strict, never coerced;
    # - `dump(value, mapper, path)` — the value as plain Hash/Array/scalar data;
    # - `accepts?(value)` — whether a default fits, checked once when the class is first read;
    # - `limits` — which of `constrain`'s `in:` / `format:` the type can take.
    #
    # `to_s` is the RBS spelling, used in every message.
    #
    # @api private
    module Type
      # @param type [#to_s] the expected type
      # @param value [Object] what was found instead
      # @param path [String]
      # @raise [DataError] always
      def self.mismatch(type, value, path)
        shown = value.inspect
        shown = "#{shown[0, 60]}…" if shown.length > 61
        raise DataError.new(path, "expected #{type}, got #{shown}")
      end

      # @param path [String]
      # @param key [String, Symbol]
      # @return [String] the path of `key` under `path`
      def self.child(path, key)
        path.empty? ? key.to_s : "#{path}.#{key}"
      end

      # `Integer`, `Float` or `String`: the value must be an instance, as it is. An Integer is not
      # a Float; `70.0` is not an Integer.
      #
      # @!attribute [r] klass
      #   @return [Class] `Integer`, `Float` or `String`
      Scalar = Data.define(:klass) do
        def load(value, path, _session, _base) = (value.is_a?(klass) ? value : Type.mismatch(self, value, path))
        def dump(value, _mapper, path) = (value.is_a?(klass) ? value : Type.mismatch(self, value, path))
        def accepts?(value) = value.is_a?(klass)
        def limits = klass == String ? %i[in format] : %i[in]
        def numeric? = klass != String
        def nested_classes = []
        def to_s = klass.name
      end

      # `bool`: `true` or `false`.
      Bool = Data.define do
        def load(value, path, _session, _base) = (accepts?(value) ? value : Type.mismatch(self, value, path))
        def dump(value, _mapper, path) = (accepts?(value) ? value : Type.mismatch(self, value, path))
        def accepts?(value) = [true, false].include?(value)
        def limits = []
        def numeric? = false
        def nested_classes = []
        def to_s = "bool"
      end

      # A union of literals, `"short" | "verbose"`: the value must equal one of them, class
      # included — `1.0` is not `1`.
      #
      # @!attribute [r] values
      #   @return [Array<String, Integer, Float, Boolean>]
      Literals = Data.define(:values) do
        def load(value, path, _session, _base) = (accepts?(value) ? value : Type.mismatch(self, value, path))
        def dump(value, _mapper, path) = (accepts?(value) ? value : Type.mismatch(self, value, path))
        def accepts?(value) = values.any? { |literal| literal.eql?(value) }
        def limits = []
        def numeric? = false
        def nested_classes = []
        def to_s = values.map(&:inspect).join(" | ")
      end

      # `T?`: `nil`, or a `T`.
      #
      # @!attribute [r] inner
      #   @return [Object] the type of a non-nil value
      Optional = Data.define(:inner) do
        def load(value, path, session, base) = (value.nil? ? nil : inner.load(value, path, session, base))
        def dump(value, mapper, path) = (value.nil? ? nil : inner.dump(value, mapper, path))
        def accepts?(value) = value.nil? || inner.accepts?(value)
        def limits = inner.limits
        def numeric? = inner.numeric?
        def nested_classes = inner.nested_classes
        def to_s = inner.is_a?(Literals) && inner.values.size > 1 ? "(#{inner})?" : "#{inner}?"
      end

      # `Array[T]`: an Array whose every element is a `T`; an element's path is `key[3]`.
      #
      # @!attribute [r] element
      #   @return [Object] the elements' type
      ArrayOf = Data.define(:element) do
        def load(value, path, session, _base)
          Type.mismatch(self, value, path) unless value.is_a?(Array)
          value.each_with_index.map { |item, i| element.load(item, "#{path}[#{i}]", session, nil) }
        end

        def dump(value, mapper, path)
          Type.mismatch(self, value, path) unless value.is_a?(Array)
          value.each_with_index.map { |item, i| element.dump(item, mapper, "#{path}[#{i}]") }
        end

        def accepts?(value) = value.is_a?(Array) && value.all? { |item| element.accepts?(item) }
        def limits = []
        def numeric? = false
        def nested_classes = element.nested_classes
        def to_s = "Array[#{element}]"
      end

      # `Hash[String, T]`: a table with String keys (a Symbol key is taken as its String) and a
      # `T` under each.
      #
      # @!attribute [r] value
      #   @return [Object] the values' type
      HashOf = Data.define(:value) do
        def load(raw, path, session, _base)
          Type.mismatch(self, raw, path) unless raw.is_a?(Hash)
          Type.string_keys(raw, path).to_h { |key, item| [key, value.load(item, Type.child(path, key), session, nil)] }
        end

        def dump(raw, mapper, path)
          Type.mismatch(self, raw, path) unless raw.is_a?(Hash)
          Type.string_keys(raw, path).to_h { |key, item| [key, value.dump(item, mapper, Type.child(path, key))] }
        end

        def accepts?(raw) = raw.is_a?(Hash) && raw.all? { |key, item| key.is_a?(String) && value.accepts?(item) }
        def limits = []
        def numeric? = false
        def nested_classes = value.nested_classes
        def to_s = "Hash[String, #{value}]"
      end

      # A class of the app's own — a data class or an accessor class — loaded from a table by
      # the mapper, recursively.
      #
      # @!attribute [r] klass
      #   @return [Class]
      ClassRef = Data.define(:klass) do
        def load(value, path, session, base)
          Type.mismatch(self, value, path) unless value.is_a?(Hash)
          session.load_object(klass, value, path, base)
        end

        def dump(value, mapper, path)
          Type.mismatch(self, value, path) unless value.is_a?(klass)
          mapper.dump_object(value, path)
        end

        def accepts?(value) = value.is_a?(klass)
        def limits = []
        def numeric? = false
        def nested_classes = [klass]
        def to_s = klass.name || klass.inspect
      end

      # A table's keys as Strings, a Symbol key taken as its String.
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
