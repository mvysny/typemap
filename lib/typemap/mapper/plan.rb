# frozen_string_literal: true

module Typemap
  class Mapper
    # One mappable property: its name, its {Type}, its {Limits}, and whether `required:` was given.
    #
    # @!attribute [r] name
    #   @return [Symbol]
    # @!attribute [r] type
    #   @return [Object] a {Type}
    # @!attribute [r] limits
    #   @return [Limits]
    # @!attribute [r] required
    #   @return [Boolean] `constrain required: true`: a loaded or dumped object must not hold `nil`
    #
    # @api private
    Property = Data.define(:name, :type, :limits, :required)

    # What the mapper knows about one class, worked out once — when the class is first read —
    # and checked then, whatever a file will hold: the shape, every property with its type and
    # limits, and the bare `new`'s values. Building it raises {DefinitionError} for a class that
    # cannot be mapped.
    #
    # A data class with a required keyword has no bare `new`: {#check_default} runs on each
    # load's base instead.
    #
    # @!attribute [r] klass
    #   @return [Class]
    # @!attribute [r] shape
    #   @return [Module] {DataShape} or {AccessorShape}
    # @!attribute [r] properties
    #   @return [Array<Property>] in declaration order
    # @!attribute [r] required_keywords
    #   @return [Array<Symbol>] the keywords a data class cannot build without; a load with no base
    #     must find each in the file
    # @!attribute [r] unknown
    #   @return [Symbol, nil] the class's `unknown` policy, `:raise` or `:ignore`; `nil` follows
    #     `load`'s `unknown:`
    #
    # @api private
    Plan = Data.define(:klass, :shape, :properties, :required_keywords, :unknown) do
      # @param klass [Class]
      # @param types [#type_for] the mapper's type strategy
      # @return [Plan]
      # @raise [DefinitionError]
      def self.build(klass, types)
        raise DefinitionError, "#{klass.inspect} is not a class" unless klass.is_a?(Class)

        shape = shape_for(klass)
        names = property_names(klass, shape)
        constraints = Constrain.constraints_for(klass)
        stray = constraints.keys - names
        raise DefinitionError, "#{klass}: constrain names #{stray.join(", ")}, not a property" unless stray.empty?

        shape.check_required_option(klass, constraints.select { |_, constraint| constraint.required }.keys)
        required_keywords = shape.required_keywords(klass, names)
        default = bare_new(klass) if required_keywords.empty?
        properties = names.map { |name| property(klass, name, constraints[name], types) }
        plan = new(klass: klass, shape: shape, properties: properties, required_keywords: required_keywords,
                   unknown: Constrain.unknown_for(klass))
        plan.check_default(default) if default
        plan
      end

      # @param klass [Class]
      # @return [Module] {DataShape} or {AccessorShape}
      def self.shape_for(klass) = klass < Data ? DataShape : AccessorShape

      # @raise [DefinitionError] unless `klass.new` works with no arguments
      def self.bare_new(klass)
        klass.new
      rescue ArgumentError => e
        raise DefinitionError, "#{klass}: must build with a bare new, its default instance (#{e.message})"
      end

      # @param klass [Class]
      # @param shape [Module] {DataShape} or {AccessorShape}
      # @return [Array<Symbol>] the mapped properties, `ignore`d ones left out
      # @raise [DefinitionError] on an `ignore` naming no property, or no property left
      def self.property_names(klass, shape)
        all = shape.properties(klass)
        ignored = Constrain.ignored_for(klass)
        stray = ignored - all
        raise DefinitionError, "#{klass}: ignore names #{stray.join(", ")}, not a property" unless stray.empty?

        names = all - ignored
        raise DefinitionError, "#{klass} has no properties: neither a data class nor an accessor class" if names.empty?

        names
      end

      def self.property(klass, name, constraint, types)
        type = types.type_for(klass, name, constraint)
        limits = if constraint
                   Limits.new(in: constraint.in, format: constraint.format,
                              not_blank: constraint.not_blank || false, not_empty: constraint.not_empty || false,
                              unique: constraint.unique || false, unique_by: constraint.unique_by)
                 else
                   Limits.none
                 end
        limits.check_against(type)
        required = constraint&.required || false
        if required && !type.accepts?(nil)
          raise DefinitionError, "required: on #{type}, which can never be missing; required: takes a " \
                                 "#{type}? defaulting to nil"
        end
        Property.new(name: name, type: type, limits: limits, required: required)
      rescue DefinitionError => e
        raise DefinitionError, "#{klass}##{name}: #{e.message}"
      end

      # Checks the values of a default instance — the bare `new`, or a load's base built from the
      # required keywords alone — against their types and limits; a required keyword's value is
      # the file's, so it is left to the load.
      #
      # @param default [Object] an instance of {#klass}
      # @return [void]
      # @raise [DefinitionError] naming `Klass#property`
      def check_default(default)
        properties.each do |property|
          next if required_keywords.include?(property.name)

          value = shape.read(default, property.name)
          check_default_value(property, value)
        rescue DefinitionError => e
          raise DefinitionError, "#{klass}##{property.name}: #{e.message}"
        end
      end

      # @return [Array<Class>] the classes of nested properties, to be planned too
      def nested_classes = properties.flat_map { |property| property.type.nested_classes }.uniq

      # @return [Array<Symbol>]
      def names = properties.map(&:name)

      # @param base [Object] an instance of {#klass}, supplying every value not loaded; never changed
      # @param loaded [Hash{Symbol => Object}] the values read from the file
      # @return [Object] a new instance
      def build(base, loaded)
        shape == DataShape ? shape.build(klass, base, loaded) : shape.build(klass, base, loaded, names)
      end

      private

      def check_default_value(property, value)
        if property.required && !value.nil?
          raise DefinitionError, "required: its default must be nil, so a file that leaves the key out fails, " \
                                 "not #{value.inspect}"
        end
        unless property.type.accepts?(value)
          raise DefinitionError, "its default #{value.inspect} does not fit #{property.type}"
        end

        property.limits.check(value, "")
        property.limits.check_unique(value, property.type, "", nil)
      rescue DataError => e
        raise DefinitionError, "its default #{e.message}"
      end
    end
  end
end
