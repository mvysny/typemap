# frozen_string_literal: true

module Typemap
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

      # Raises in words a person editing the file reads, not Ruby's `1..`:
      #
      #     must be 1 to 100, got 170                  # in: 1..100
      #     must be at least 1 and below 10, got 10    # in: 1...10
      #     must be one of "short", "verbose", got "x" # in: %w[short verbose]
      #
      # @param value [Object] a value that has already passed the type
      # @param path [String]
      # @return [void]
      # @raise [DataError] if the value is outside the limits
      def check(value, path)
        return if value.nil?

        allowed = self.in
        if allowed.is_a?(Range) && !allowed.cover?(value)
          raise DataError.new(path, "must be #{Limits.range_words(allowed)}, got #{value.inspect}")
        end
        if allowed.is_a?(Array) && !allowed.include?(value)
          raise DataError.new(path, "must be one of #{allowed.map(&:inspect).join(", ")}, got #{value.inspect}")
        end
        return unless format && !format.match?(value)

        raise DataError.new(path, "#{value.inspect} does not match #{format.inspect}")
      end

      # @param range [Range] a numeric range; an endless or beginless one too
      # @return [String] `1 to 100`, `at least 1`, `at most 100`, `below 10`, `at least 1 and below 10`
      def self.range_words(range)
        from = range.begin&.inspect
        to = range.end&.inspect
        upper = range.exclude_end? ? "below #{to}" : "at most #{to}"
        if from && to
          range.exclude_end? ? "at least #{from} and #{upper}" : "#{from} to #{to}"
        elsif from
          "at least #{from}"
        else
          upper
        end
      end

      private

      def numeric_range?(range, type)
        type.numeric? && [range.begin, range.end].all? { |end_| end_.nil? || end_.is_a?(Numeric) }
      end
    end
  end
end
