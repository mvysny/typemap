# frozen_string_literal: true

# An anonymous accessor class with one property, `value`, of the given type, default and options.
module Holder
  # @param type [String] the RBS type string
  # @param default [Object] what a bare `new` sets
  # @param limits [Hash] `constrain`'s other options: `in:`, `not_blank:`, `required:`…
  # @return [Class]
  def self.of(type, default, **limits)
    klass = Class.new do
      extend Typemap::Constrain

      attr_accessor :value

      define_method(:initialize) { @value = default }
    end
    klass.constrain(:value, type: type, **limits)
    klass
  end
end
