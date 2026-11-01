# frozen_string_literal: true

module Confect
  class Mapper
    # `constrain`'s `in:` and `format:` for one property, checked after its type. A `nil` value
    # (of a `T?` type) is never limited.
    #
    # @!attribute [r] in
    #   @return [Range, Array, nil] the allowed range of a number, or the allowed values
    # @!attribute [r] format
    #   @return [Regexp, nil] the pattern a String must match
    #
    # @api private
    Limits = Data.define(:in, :format) do
      # @return [Limits] no limits at all
      def self.none = new(in: nil, format: nil)

      # Raises unless the type can take these limits: `in:` a Range on a number, `in:` an Array
      # on a number or a String, `format:` on a String.
      #
      # @param type [Object] the property's {Type}
      # @return [void]
      # @raise [DefinitionError]
      def check_against(type)
        allowed = self.in
        unless allowed.nil? || type.limits.include?(:in)
          raise DefinitionError, "in: #{allowed.inspect} cannot limit #{type}"
        end
        if allowed.is_a?(Range) && !numeric_range?(allowed, type)
          raise DefinitionError,
                "in: #{allowed.inspect} is a range, so it limits only a number with number ends, not #{type}"
        end
        return if format.nil? || type.limits.include?(:format)

        raise DefinitionError, "format: #{format.inspect} limits only a String, not #{type}"
      end

      # @param value [Object] a value that has already passed the type
      # @param path [String]
      # @return [void]
      # @raise [DataError] if the value is outside the limits
      def check(value, path)
        return if value.nil?

        allowed = self.in
        if allowed.is_a?(Range) && !allowed.cover?(value)
          raise DataError.new(path, "#{value.inspect} is not in #{allowed.inspect}")
        end
        if allowed.is_a?(Array) && !allowed.include?(value)
          raise DataError.new(path, "#{value.inspect} is not one of #{allowed.inspect}")
        end
        return unless format && !format.match?(value)

        raise DataError.new(path, "#{value.inspect} does not match #{format.inspect}")
      end

      private

      def numeric_range?(range, type)
        type.numeric? && [range.begin, range.end].all? { |end_| end_.nil? || end_.is_a?(Numeric) }
      end
    end
  end
end
