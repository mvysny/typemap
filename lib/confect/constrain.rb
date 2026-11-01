# frozen_string_literal: true

module Confect
  # The class-side annotations the mapper reads: `extend Confect::Constrain`, then
  #
  #     constrain :raise_at_percent, :shrink_at_percent, type: "Integer", in: 1..100
  #     constrain :pinned_vms, type: "Array[String]"
  #     ignore :on_change
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
    Constraint = Data.define(:type, :type_owner, :in, :format)

    # Records a type and limits for one or more properties; several calls for one property merge,
    # but one option given twice raises.
    #
    # @param names [Array<Symbol>] the properties
    # @param type [String, nil] an RBS type string, `"Integer"`, `"String?"`, `"Array[String]"`;
    #   never a Ruby class, so nil-ability is always spelled out (`D_types_declared`)
    # @param in [Range, Array, nil] the allowed range of a number, or the allowed values
    # @param format [Regexp, nil] the pattern a String must match
    # @return [void]
    # @raise [ArgumentError] on no names, nothing to record, a wrongly typed option, or an option
    #   already given for that property
    def constrain(*names, type: nil, in: nil, format: nil)
      allowed = binding.local_variable_get(:in)
      check_constrain_args(names, type, allowed, format)
      given = { type: type, in: allowed, format: format }.compact
      given[:type_owner] = self if type
      names.each do |name|
        entry = confect_constraints[name] ||= {}
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
      confect_ignored.concat(names - confect_ignored)
    end

    # @api private
    # @return [Hash{Symbol => Hash}] what `constrain` recorded on this class itself
    def confect_constraints
      @confect_constraints ||= {}
    end

    # @api private
    # @return [Array<Symbol>] what `ignore` recorded on this class itself
    def confect_ignored
      @confect_ignored ||= []
    end

    # The constraints of `klass` and its ancestors, a subclass's option winning over its
    # superclass's.
    #
    # @param klass [Class]
    # @return [Hash{Symbol => Constraint}]
    def self.constraints_for(klass)
      merged = {}
      klass.ancestors.reverse_each do |mod|
        next unless mod.singleton_class.include?(Constrain)

        mod.confect_constraints.each { |name, options| (merged[name] ||= {}).merge!(options) }
      end
      merged.transform_values do |options|
        Constraint.new(type: options[:type], type_owner: options[:type_owner], in: options[:in],
                       format: options[:format])
      end
    end

    # @param klass [Class]
    # @return [Array<Symbol>] the names `klass` and its ancestors `ignore`
    def self.ignored_for(klass)
      klass.ancestors.select { |mod| mod.singleton_class.include?(Constrain) }.flat_map(&:confect_ignored).uniq
    end

    private

    def check_constrain_args(names, type, allowed, format)
      raise ArgumentError, "constrain: name at least one property" if names.empty?

      names.each do |name|
        raise ArgumentError, "constrain: #{name.inspect} is not a Symbol" unless name.is_a?(Symbol)
      end
      if [type, allowed, format].all?(&:nil?)
        raise ArgumentError, "constrain #{names.inspect}: give type:, in: or format:"
      end
      unless type.nil? || type.is_a?(String)
        raise ArgumentError, "constrain: type: must be an RBS type String, got #{type.inspect}"
      end
      unless allowed.nil? || allowed.is_a?(Range) || allowed.is_a?(Array)
        raise ArgumentError, "constrain: in: must be a Range or an Array, got #{allowed.inspect}"
      end
      return if format.nil? || format.is_a?(Regexp)

      raise ArgumentError, "constrain: format: must be a Regexp, got #{format.inspect}"
    end
  end
end
