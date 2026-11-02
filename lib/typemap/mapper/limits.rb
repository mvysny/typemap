# frozen_string_literal: true

module Typemap
  class Mapper
    # `constrain`'s limits for one property, checked after its type. A `nil` value (of a `T?`
    # type) is never limited.
    #
    # @!attribute [r] in
    #   @return [Range, Array, nil] the allowed range of a number, or the allowed values
    # @!attribute [r] format
    #   @return [Regexp, nil] the pattern a String must match
    # @!attribute [r] not_blank
    #   @return [Boolean] a String must hold more than whitespace
    # @!attribute [r] not_empty
    #   @return [Boolean] an Array or a Hash must hold at least one element
    #
    # @api private
    Limits = Data.define(:in, :format, :not_blank, :not_empty) do
      # @return [Limits] no limits at all
      def self.none = new(in: nil, format: nil, not_blank: false, not_empty: false)

      # Raises unless the type can take these limits: `in:` a Range on a number, `in:` an Array
      # on a number or a String, `format:` and `not_blank:` on a String, `not_empty:` on an Array
      # or a Hash.
      #
      # @param type [Object] the property's {Type}
      # @return [void]
      # @raise [DefinitionError]
      def check_against(type)
        check_in_against(type)
        if format && !type.limits.include?(:format)
          raise DefinitionError, "format: #{format.inspect} limits only a String, not #{type}"
        end

        if not_blank && !type.limits.include?(:not_blank)
          hint = ("; an Array or a Hash takes not_empty:" if type.limits.include?(:not_empty))
          raise DefinitionError, "not_blank: limits only a String, not #{type}#{hint}"
        end
        return unless not_empty && !type.limits.include?(:not_empty)

        # A String takes not_empty: in Bean Validation; here it would pass "  ", the typo
        # not_blank: exists to catch.
        hint = ("; a String takes not_blank:, which refuses \"  \" too" if type.limits.include?(:not_blank))
        raise DefinitionError, "not_empty: limits only an Array or a Hash, not #{type}#{hint}"
      end

      # Raises in words a person editing the file reads, not Ruby's `1..`:
      #
      #     must be 1 to 100, got 170                  # in: 1..100
      #     must be at least 1 and below 10, got 10    # in: 1...10
      #     must be one of "short", "verbose", got "x" # in: %w[short verbose]
      #     must not be blank                          # not_blank: true, got "  "
      #     must not be empty                          # not_empty: true, got []
      #
      # @param value [Object] a value that has already passed the type
      # @param path [String]
      # @return [void]
      # @raise [DataError] if the value is outside the limits
      def check(value, path)
        return if value.nil?

        raise DataError.new(path, "must not be blank") if not_blank && value.strip.empty?
        raise DataError.new(path, "must not be empty") if not_empty && value.empty?

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

      def check_in_against(type)
        allowed = self.in
        unless allowed.nil? || type.limits.include?(:in)
          raise DefinitionError, "in: #{allowed.inspect} cannot limit #{type}"
        end
        return unless allowed.is_a?(Range) && !numeric_range?(allowed, type)

        raise DefinitionError,
              "in: #{allowed.inspect} is a range, so it limits only a number with number ends, not #{type}"
      end

      def numeric_range?(range, type)
        type.numeric? && [range.begin, range.end].all? { |end_| end_.nil? || end_.is_a?(Numeric) }
      end
    end
  end
end
