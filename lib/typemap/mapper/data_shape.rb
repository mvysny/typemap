# frozen_string_literal: true

module Typemap
  class Mapper
    # The shape of a data class (`Data.define`): its properties are its `members`, in order, and
    # an instance is built in one `new(**values)`.
    #
    # @api private
    module DataShape
      # @param klass [Class] a `Data` subclass
      # @return [Array<Symbol>] its members, in declaration order
      def self.properties(klass) = klass.members

      # @param object [Data]
      # @param name [Symbol]
      # @return [Object] the property's value
      def self.read(object, name) = object.public_send(name)

      # @param klass [Class]
      # @param base [Data] supplies every value `loaded` does not
      # @param loaded [Hash{Symbol => Object}] the values read from the file
      # @return [Data]
      def self.build(klass, base, loaded)
        klass.new(**klass.members.to_h { |name| [name, base.public_send(name)] }, **loaded)
      end
    end
  end
end
