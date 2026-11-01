# frozen_string_literal: true

module Confect
  class Mapper
    # One mappable property: its name, its {Type} and its {Limits}.
    #
    # @!attribute [r] name
    #   @return [Symbol]
    # @!attribute [r] type
    #   @return [Object] a {Type}
    # @!attribute [r] limits
    #   @return [Limits]
    #
    # @api private
    Property = Data.define(:name, :type, :limits)

    # What the mapper knows about one class, worked out once — when the class is first read —
    # and checked then, whatever a file will hold: the shape, and every property with its type
    # and limits. Building it raises {DefinitionError} for a class that cannot be mapped.
    #
    # @!attribute [r] klass
    #   @return [Class]
    # @!attribute [r] shape
    #   @return [Module] {DataShape} or {AccessorShape}
    # @!attribute [r] properties
    #   @return [Array<Property>] in declaration order
    #
    # @api private
    Plan = Data.define(:klass, :shape, :properties) do
      # @param klass [Class]
      # @param types [#type_for] the mapper's type strategy
      # @return [Plan]
      # @raise [DefinitionError]
      def self.build(klass, types)
        raise DefinitionError, "#{klass.inspect} is not a class" unless klass.is_a?(Class)

        shape = klass < Data ? DataShape : AccessorShape
        default = bare_new(klass)
        names = property_names(klass, shape)
        constraints = Constrain.constraints_for(klass)
        stray = constraints.keys - names
        raise DefinitionError, "#{klass}: constrain names #{stray.join(", ")}, not a property" unless stray.empty?

        properties = names.map { |name| property(klass, shape, default, name, constraints[name], types) }
        new(klass: klass, shape: shape, properties: properties)
      end

      # @raise [DefinitionError] unless `klass.new` works with no arguments
      def self.bare_new(klass)
        klass.new
      rescue ArgumentError => e
        raise DefinitionError, "#{klass}: must build with a bare new, its default instance (#{e.message})"
      end

      def self.property_names(klass, shape)
        all = shape.properties(klass)
        ignored = Constrain.ignored_for(klass)
        stray = ignored - all
        raise DefinitionError, "#{klass}: ignore names #{stray.join(", ")}, not a property" unless stray.empty?

        names = all - ignored
        raise DefinitionError, "#{klass} has no properties: neither a data class nor an accessor class" if names.empty?

        names
      end

      def self.property(klass, shape, default, name, constraint, types)
        type = types.type_for(klass, name, constraint)
        limits = constraint ? Limits.new(in: constraint.in, format: constraint.format) : Limits.none
        limits.check_against(type)
        value = shape.read(default, name)
        raise DefinitionError, "its default #{value.inspect} does not fit #{type}" unless type.accepts?(value)

        begin
          limits.check(value, "")
        rescue DataError => e
          raise DefinitionError, "its default #{e.message}"
        end
        Property.new(name: name, type: type, limits: limits)
      rescue DefinitionError => e
        raise DefinitionError, "#{klass}##{name}: #{e.message}"
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
    end
  end
end
