# frozen_string_literal: true

module Typemap
  class Mapper
    # The shape of an accessor class — a mutable class built by a bare `new` and then its
    # setters. Its properties are its public reader + writer pairs (`D_accessor_properties`):
    # only methods count, never ivars, and a private or protected accessor is left out.
    #
    # @api private
    module AccessorShape
      READER = /\A[a-z_][A-Za-z0-9_]*\z/
      private_constant :READER

      # Public reader + writer pairs in declaration order: sorted by the reader's source line,
      # since `public_instance_methods` comes in no declared order (`R_ruby_reflection`), and
      # within one line — `attr_accessor :a, :b` — by where the name stands in it, read from the
      # source file. A reader with no source location (one defined in C) sorts last, by name.
      #
      # @param klass [Class]
      # @return [Array<Symbol>]
      def self.properties(klass)
        names = klass.public_instance_methods.select do |name|
          name.match?(READER) && klass.public_method_defined?(:"#{name}=") && klass.instance_method(name).arity.zero?
        end
        sources = Hash.new { |cache, file| cache[file] = File.exist?(file) ? File.readlines(file) : [] }
        names.sort_by do |name|
          file, line = klass.instance_method(name).source_location
          next [1, "", 0, 0, name.to_s] unless file

          column = sources[file][line - 1]&.index(/\b#{name}\b/) || 0
          [0, file, line, column, name.to_s]
        end
      end

      # A bare `new` sets every property, so none is required by the class itself; `required:`
      # says it instead.
      #
      # @param _klass [Class]
      # @param _names [Array<Symbol>]
      # @return [Array<Symbol>] always empty
      def self.required_keywords(_klass, _names) = []

      # @param _klass [Class]
      # @param _names [Array<Symbol>] the properties `constrain` gave `required:`
      # @return [void]
      def self.check_required_option(_klass, _names) = nil

      # @param object [Object]
      # @param name [Symbol]
      # @return [Object] the property's value
      def self.read(object, name) = object.public_send(name)

      # Leaves a property's value mutable, as the class is (`D_frozen_containers`).
      #
      # @param _value [Object]
      # @return [void]
      def self.freeze_value(_value) = nil

      # A fresh bare `new`, then a setter for every property: `base`'s value, or the loaded one.
      # `base` itself is never changed — it may be a default shared beyond this load.
      #
      # @param klass [Class]
      # @param base [Object] supplies every value `loaded` does not
      # @param loaded [Hash{Symbol => Object}] the values read from the file
      # @param names [Array<Symbol>] the mapped properties
      # @return [Object]
      def self.build(klass, base, loaded, names)
        object = klass.new
        names.each { |name| object.public_send(:"#{name}=", loaded.fetch(name) { base.public_send(name) }) }
        object
      end
    end
  end
end
