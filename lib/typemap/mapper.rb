# frozen_string_literal: true

require "did_you_mean" # a default gem; `ruby --disable-did_you_mean` leaves it unloaded
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
  # pairs); its bare `new` is the default instance. A key the file must give is a data class's
  # keyword without a default, or an accessor class's `constrain required: true`. Types are
  # strict: `"70"` is not an Integer and `70.5` is not 70, though a whole `70.0` loads as 70 and
  # `1` as a Float `1.0`. The first problem raises — a {DataError} with the offending value's
  # path when the file does not fit, a {DefinitionError} when the class cannot be mapped, the
  # latter as soon as the class is first read.
  #
  # Both `load` and `dump` validate the whole result once it is built, objects the file left out
  # included, nested objects first: per object the `in:` / `format:` limits, `required:`, then
  # the object's own `validate`, if it has one.
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
    # absent keeps it; a nested Hash loads onto the default's nested object. Then validates it.
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

      object = Session.new(mapper: self, unknown: unknown).load_object(klass, hash, "", nil)
      validate_object(object, "")
      object
    end

    # Converts `object`, then validates it, so nothing comes back that a later {#load} would
    # reject.
    #
    # @param object [Object] an instance of a data class or an accessor class
    # @return [Hash{String => Object}] its properties, in declaration order, as plain data —
    #   String keys, nested objects as Hashes — ready for `JSON.generate`
    # @raise [DataError] if a property holds a value its type rejects, a value outside its limits,
    #   `nil` where `required:`, or the object's `validate` raises
    # @raise [DefinitionError] if the class cannot be mapped
    def dump(object)
      hash = dump_object(object, "")
      validate_object(object, "")
      hash
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

    # `object` as {#dump_object} gives it, less any property whose value won't dump: the `raw` an
    # array entry's `entry_name` takes when the entry is an object, in validation and dump.
    #
    # @api private
    # @param object [Object] an instance of a mapped class
    # @return [Hash{String => Object}]
    def entry_hash(object)
      plan = plan_for(object.class)
      plan.properties.each_with_object({}) do |property, hash|
        hash[property.name.to_s] = property.type.dump(plan.shape.read(object, property.name), self, "")
      rescue DataError
        next # likely the very value being reported; the name does without it
      end
    end

    # Validates a converted object, nested objects first; changes nothing. Types are not
    # rechecked: conversion did that, and the limits assume it.
    #
    # @api private
    # @param object [Object]
    # @param path [String] where `object` sits, for messages
    # @return [void]
    # @raise [DataError]
    def validate_object(object, path)
      plan = plan_for(object.class)
      values = plan.properties.to_h { |property| [property, plan.shape.read(object, property.name)] }
      values.each do |property, value|
        property.type.each_object(value, self, Type.child(path, property.name)) do |nested, at|
          validate_object(nested, at)
        end
      end
      check_values(values, path)
      call_validate(object, path)
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

    private

    def check_values(values, path)
      values.each do |property, value|
        child = Type.child(path, property.name)
        property.limits.check(value, child)
        raise DataError.new(child, "required") if property.required && value.nil?
      end
    end

    def call_validate(object, path)
      object.validate if object.respond_to?(:validate)
    rescue Error
      raise
    rescue StandardError => e
      raise DataError.new(path, e.message)
    end

    # One `load` call's conversion: the mapper and the `unknown:` policy every nested object shares.
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
      # @param base [Object, nil] the default to load onto; `nil` builds a fresh one
      # @return [Object] an instance of `klass`
      # @raise [DataError]
      def load_object(klass, raw, path, base)
        plan = mapper.plan_for(klass)
        Type.mismatch(klass, raw, path) unless raw.is_a?(Hash)
        values = Type.string_keys(raw, path)
        reject_unknown(plan, values, path)
        base, loaded = base ? [base, {}] : fresh_base(plan, values, path)
        plan.properties.each do |property|
          key = property.name.to_s
          next if !values.key?(key) || loaded.key?(property.name)

          base_value = plan.shape.read(base, property.name)
          loaded[property.name] = property.type.load(values[key], Type.child(path, key), self, base_value)
        end
        plan.build(base, loaded)
      end

      private

      # A bare `new`; or, for a data class with required keywords, `new` given just those, loaded
      # first from the file — a nested one onto its own class's defaults, there being no other.
      #
      # @return [Array(Object, Hash{Symbol => Object})] the base, and the values loaded for it
      def fresh_base(plan, values, path)
        return [plan.klass.new, {}] if plan.required_keywords.empty?

        loaded = plan.properties.select { |property| plan.required_keywords.include?(property.name) }.to_h do |property|
          key = property.name.to_s
          child = Type.child(path, key)
          raise DataError.new(child, "required") unless values.key?(key)

          [property.name, property.type.load(values[key], child, self, nil)]
        end
        base = plan.klass.new(**loaded)
        plan.check_default(base)
        [base, loaded]
      end

      # `rasie_at_percent: unknown key, did you mean raise_at_percent?`; with no close match,
      # `rasie: unknown key; Ballooning has raise_at_percent, shrink_at_percent`.
      def reject_unknown(plan, values, path)
        return if unknown == :ignore

        names = plan.names.map(&:to_s)
        key = (values.keys - names).first
        return if key.nil?

        guesses = DidYouMean::SpellChecker.new(dictionary: names).correct(key)
        detail = if guesses.empty?
                   "unknown key; #{plan.klass} has #{names.join(", ")}"
                 else
                   "unknown key, did you mean #{guesses.join(" or ")}?"
                 end
        raise DataError.new(Type.child(path, key), detail)
      end
    end
  end
end
