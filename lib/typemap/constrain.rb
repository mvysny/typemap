# frozen_string_literal: true

module Typemap
  # The class-side annotations the mapper reads: `extend Typemap::Constrain`, then
  #
  #     constrain :raise_at_percent, :shrink_at_percent, type: "Integer", in: 1..100
  #     constrain :pinned_vms, type: "Array[String]"
  #     constrain :api_key, type: "String?", required: true   # an accessor class's nil default
  #     constrain :url, type: "String", not_blank: true        # not "" and not "  "
  #     constrain :servers, type: "Array[Server]", unique_by: :id
  #     ignore :on_change
  #     unknown :ignore                                         # keys this app does not read
  #
  # Each call records metadata and defines nothing — no accessor, no default, no `initialize`;
  # the class stays as written (`D_constrain_macro`). An unknown option is Ruby's own
  # `ArgumentError` the moment the class body runs.
  module Constrain
    # What `constrain` recorded for one property.
    #
    # @!attribute [r] type
    #   @return [String, nil] the RBS type string, `nil` when the type comes from elsewhere
    # @!attribute [r] type_owner
    #   @return [Module, nil] the class that gave `type:`; its namespace resolves the names in it
    # @!attribute [r] in
    #   @return [Range, Array, nil] the allowed range, or the allowed values
    # @!attribute [r] format
    #   @return [Regexp, nil] the pattern a String must match
    # @!attribute [r] not_blank
    #   @return [true, nil] a String must hold more than whitespace
    # @!attribute [r] not_empty
    #   @return [true, nil] an Array or a Hash must hold at least one element
    # @!attribute [r] unique
    #   @return [true, nil] no two entries of an Array may be equal
    # @!attribute [r] unique_by
    #   @return [Symbol, Proc, nil] what of an Array's entry no two entries may share
    # @!attribute [r] required
    #   @return [Boolean, nil] whether a loaded or dumped object must hold a non-nil value
    Constraint = Data.define(:type, :type_owner, :in, :format, :not_blank, :not_empty, :unique, :unique_by,
                             :required)

    # Records a type and limits for one or more properties; several calls for one property merge,
    # but one option given twice raises.
    #
    # @param names [Array<Symbol>] the properties
    # @param type [String, nil] an RBS type string, `"Integer"`, `"String?"`, `"Array[String]"`;
    #   never a Ruby class, so nil-ability is always spelled out (`D_types_declared`)
    # @param in [Range, Array, nil] the allowed range of a number, or the allowed values
    # @param format [Regexp, nil] the pattern a String must match
    # @param not_blank [true, nil] `true`: a String must hold more than whitespace (`strip.empty?`
    #   fails it). Bean Validation's `@NotBlank`, except that a `String?`'s `nil` passes.
    # @param not_empty [true, nil] `true`: an Array or a Hash must hold an element; a String
    #   takes `not_blank:` instead
    # @param unique [true, nil] `true`: no two entries of an Array may be equal (`eql?`), `nil`s
    #   included; entries of a class need value equality, as a data class has
    # @param unique_by [Symbol, Proc, nil] what no two entries of an Array may share: a property
    #   of the entries' class, `:id`, or a function of the entry, `->(s) { s.url.downcase }`
    # @param required [Boolean, nil] `true`: the file must give this key, on an accessor class
    #   whose property is a `T?` defaulting to `nil` — a loaded or dumped object still holding
    #   `nil` raises. A data class says it by a keyword without a default instead.
    # @return [void]
    # @raise [ArgumentError] on no names, nothing to record, a wrongly typed option, `unique:` and
    #   `unique_by:` together, or an option already given for that property
    def constrain(*names, type: nil, in: nil, format: nil, not_blank: nil, not_empty: nil, unique: nil,
                  unique_by: nil, required: nil)
      given = { type: type, in: binding.local_variable_get(:in), format: format, not_blank: not_blank,
                not_empty: not_empty, unique: unique, unique_by: unique_by, required: required }.compact
      check_constrain_args(names, given)
      given[:type_owner] = self if type
      names.each do |name|
        entry = typemap_constraints[name] ||= {}
        given.each do |key, value|
          raise ArgumentError, "constrain :#{name}: #{key}: given twice" if entry.key?(key)

          entry[key] = value
        end
      end
    end

    # Leaves public accessors out of the mapping — a listener the app sets from outside, say. A
    # private or protected accessor is left out already.
    #
    # @param names [Array<Symbol>] the accessors to skip
    # @return [void]
    # @raise [ArgumentError] on no names, or a name that is not a Symbol
    def ignore(*names)
      raise ArgumentError, "ignore: name at least one property" if names.empty?

      names.each do |name|
        raise ArgumentError, "ignore: #{name.inspect} is not a Symbol" unless name.is_a?(Symbol)
      end
      typemap_ignored.concat(names - typemap_ignored)
    end

    # Sets what a load does with a key of this class that names no property, overriding `load`'s
    # `unknown:` both ways:
    #
    #     unknown :ignore   # a table another program owns, which may grow keys this app doesn't read
    #
    # Only this class's own keys: a class nested in it keeps its own policy, or `load`'s. A
    # subclass inherits it.
    #
    # @param policy [Symbol] `:raise` or `:ignore`, the values `load`'s `unknown:` takes
    # @return [void]
    # @raise [ArgumentError] on another value, or a second call in one class
    def unknown(policy)
      unless %i[raise ignore].include?(policy)
        raise ArgumentError, "unknown: must be :raise or :ignore, got #{policy.inspect}"
      end
      raise ArgumentError, "unknown: given twice" if typemap_unknown

      @typemap_unknown = policy
    end

    # @api private
    # @return [Hash{Symbol => Hash}] what `constrain` recorded on this class itself
    def typemap_constraints
      @typemap_constraints ||= {}
    end

    # @api private
    # @return [Array<Symbol>] what `ignore` recorded on this class itself
    def typemap_ignored
      @typemap_ignored ||= []
    end

    # @api private
    # @return [Symbol, nil] what `unknown` recorded on this class itself
    def typemap_unknown = @typemap_unknown

    # The constraints of `klass` and its ancestors, a subclass's option winning over its
    # superclass's.
    #
    # @param klass [Class]
    # @return [Hash{Symbol => Constraint}]
    def self.constraints_for(klass)
      merged = {}
      klass.ancestors.reverse_each do |mod|
        next unless mod.singleton_class.include?(Constrain)

        mod.typemap_constraints.each { |name, options| (merged[name] ||= {}).merge!(options) }
      end
      merged.transform_values do |options|
        Constraint.new(type: options[:type], type_owner: options[:type_owner], in: options[:in],
                       format: options[:format], not_blank: options[:not_blank],
                       not_empty: options[:not_empty], unique: options[:unique],
                       unique_by: options[:unique_by], required: options[:required])
      end
    end

    # @param klass [Class]
    # @return [Array<Symbol>] the names `klass` and its ancestors `ignore`
    def self.ignored_for(klass)
      klass.ancestors.select { |mod| mod.singleton_class.include?(Constrain) }.flat_map(&:typemap_ignored).uniq
    end

    # @param klass [Class]
    # @return [Symbol, nil] the `unknown` policy of `klass` or its nearest ancestor that gives one;
    #   `nil` when none does, leaving it to `load`'s `unknown:`
    def self.unknown_for(klass)
      klass.ancestors.each do |mod|
        return mod.typemap_unknown if mod.singleton_class.include?(Constrain) && mod.typemap_unknown
      end
      nil
    end

    private

    def check_constrain_args(names, given)
      raise ArgumentError, "constrain: name at least one property" if names.empty?

      names.each do |name|
        raise ArgumentError, "constrain: #{name.inspect} is not a Symbol" unless name.is_a?(Symbol)
      end
      if given.empty?
        raise ArgumentError,
              "constrain #{names.inspect}: give type:, in:, format:, not_blank:, not_empty:, unique:, " \
              "unique_by: or required:"
      end
      given.each { |key, value| check_constrain_option(key, value) }
      return unless given.key?(:unique) && given.key?(:unique_by)

      raise ArgumentError, "constrain: unique: and unique_by: together; unique_by: alone says what to compare"
    end

    def check_constrain_option(key, value)
      expected = case key
                 when :type then "an RBS type String" unless value.is_a?(String)
                 when :in then "a Range or an Array" unless value.is_a?(Range) || value.is_a?(Array)
                 when :format then "a Regexp" unless value.is_a?(Regexp)
                 when :unique_by then "a Symbol or a Proc" unless value.is_a?(Symbol) || value.is_a?(Proc)
                 when :required then "true or false" unless [true, false].include?(value)
                 # A switch: `false` would mean what leaving it out does — for the negated names, a
                 # double negative.
                 else "true, or left out" unless value == true
                 end
      raise ArgumentError, "constrain: #{key}: must be #{expected}, got #{value.inspect}" if expected
    end
  end
end
