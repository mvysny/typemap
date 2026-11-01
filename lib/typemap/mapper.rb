# frozen_string_literal: true

require "monitor"
require_relative "mapper/type"
require_relative "mapper/name_resolver"
require_relative "mapper/type_parser"
require_relative "mapper/type_builder"
require_relative "mapper/basic_types"
require_relative "mapper/rbs_types"
require_relative "mapper/data_shape"
require_relative "mapper/accessor_shape"
require_relative "mapper/limits"
require_relative "mapper/plan"

module Typemap
  # Turns a parsed file — a Hash, from `Tomlrb.load_file`, `JSON.load_file` or
  # `YAML.safe_load_file` — into an instance of a class you already wrote, and back:
  #
  #     mapper = Typemap::Mapper.new
  #     config = mapper.load(Config, Tomlrb.load_file(path))
  #     state  = mapper.load(State, JSON.load_file(path), unknown: :ignore)
  #     File.write(path, JSON.pretty_generate(mapper.dump(state)))
  #
  # The class is a data class (`Data.define`) or an accessor class (public reader + writer
  # pairs); either must build with a bare `new`, which is its default instance. Types are strict:
  # `"70"` is not an Integer and `70.5` is not 70, though a whole `70.0` loads as 70 and `1` as
  # a Float `1.0`. The first problem raises — a {DataError} with
  # the offending value's path when the file does not fit, a {DefinitionError} when the class
  # cannot be mapped, the latter as soon as the class is first read. After building an object
  # the mapper calls its `validate`, if it has one, nested objects first.
  #
  # A mapper remembers what it learnt about each class; it is safe to share between threads.
  class Mapper
    # @return [#type_for] where property types come from: {BasicTypes} or {RBSTypes}
    attr_reader :types

    # @param types [#type_for] {BasicTypes}, the default, takes every type from
    #   `constrain type:`; {RBSTypes} reads `sig/*.rbs` and needs the `rbs` gem
    def initialize(types: BasicTypes.new)
      @types = types
      @plans = {}
      @lock = Monitor.new
    end

    # Builds an instance of `klass` from `hash`: each key present replaces the default, each key
    # absent keeps it; a nested table loads onto the default's nested object.
    #
    # @param klass [Class] a data class or an accessor class
    # @param hash [Hash{String, Symbol => Object}] the parsed file
    # @param unknown [Symbol] `:raise` on a key the class has no property for, or `:ignore` it —
    #   say, a key a newer version of the app wrote
    # @return [Object] an instance of `klass`
    # @raise [DataError] if the data does not fit the class
    # @raise [DefinitionError] if the class cannot be mapped
    def load(klass, hash, unknown: :raise)
      unless %i[raise ignore].include?(unknown)
        raise ArgumentError, "unknown: must be :raise or :ignore, got #{unknown.inspect}"
      end

      Session.new(mapper: self, unknown: unknown).load_object(klass, hash, "", nil)
    end

    # @param object [Object] an instance of a data class or an accessor class
    # @return [Hash{String => Object}] its properties, in declaration order, as plain data —
    #   String keys, nested objects as Hashes — ready for `JSON.generate`
    # @raise [DataError] if a property holds a value its type rejects
    # @raise [DefinitionError] if the class cannot be mapped
    def dump(object)
      dump_object(object, "")
    end

    # @api private
    # @param object [Object]
    # @param path [String] where `object` sits, for messages
    # @return [Hash{String => Object}]
    def dump_object(object, path)
      plan = plan_for(object.class)
      plan.properties.to_h do |property|
        child = Type.child(path, property.name)
        [property.name.to_s, property.type.dump(plan.shape.read(object, property.name), self, child)]
      end
    end

    # What the mapper knows about `klass`, worked out and checked the first time it is asked,
    # together with every class nested in it.
    #
    # @api private
    # @param klass [Class]
    # @return [Plan]
    # @raise [DefinitionError]
    def plan_for(klass)
      @lock.synchronize do
        return @plans[klass] if @plans.key?(klass)

        plan = Plan.build(klass, types)
        @plans[klass] = plan # before the nested classes, so a class nested in itself terminates
        begin
          plan.nested_classes.each { |nested| plan_for(nested) }
        rescue DefinitionError
          @plans.delete(klass)
          raise
        end
        plan
      end
    end

    # One `load` call: the mapper and the `unknown:` policy every nested object shares.
    #
    # @api private
    # @!attribute [r] mapper
    #   @return [Mapper]
    # @!attribute [r] unknown
    #   @return [Symbol] `:raise` or `:ignore`
    Session = Data.define(:mapper, :unknown) do
      # @param klass [Class]
      # @param raw [Object] what the file holds for this object, expected to be a Hash
      # @param path [String] where it sits, `""` for the root
      # @param base [Object, nil] the default to load onto; `nil` builds a bare `klass.new`
      # @return [Object] an instance of `klass`
      # @raise [DataError]
      def load_object(klass, raw, path, base)
        plan = mapper.plan_for(klass)
        unless raw.is_a?(Hash)
          raise DataError.new(path,
                              "expected a table of #{klass}'s properties, got #{raw.inspect}")
        end

        values = Type.string_keys(raw, path)
        reject_unknown(plan, values, path)
        base ||= klass.new
        loaded = {}
        plan.properties.each do |property|
          key = property.name.to_s
          next unless values.key?(key)

          child = Type.child(path, key)
          value = property.type.load(values[key], child, self, plan.shape.read(base, property.name))
          property.limits.check(value, child)
          loaded[property.name] = value
        end
        validated(plan.build(base, loaded), path)
      end

      private

      def reject_unknown(plan, values, path)
        return if unknown == :ignore

        extra = values.keys - plan.names.map(&:to_s)
        return if extra.empty?

        raise DataError.new(Type.child(path, extra.first), "unknown key; #{plan.klass} has #{plan.names.join(", ")}")
      end

      def validated(object, path)
        object.validate if object.respond_to?(:validate)
        object
      rescue Error
        raise
      rescue StandardError => e
        raise DataError.new(path, e.message)
      end
    end
  end
end
