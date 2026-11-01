# frozen_string_literal: true

module Confect
  class Mapper
    # Parses a type string in the subset of RBS the mapper supports into a syntax tree for
    # {TypeBuilder}; `BasicTypes` uses it so the `rbs` gem stays optional. The grammar:
    #
    #     type    := postfix ('|' postfix)*
    #     postfix := primary '?'*
    #     primary := '(' type ')' | literal | 'bool' | 'nil' | name ('[' type (',' type)* ']')?
    #     name    := '::'? Constant ('::' Constant)*
    #     literal := "string" | 'string' | integer | true | false
    #
    # A tree node is an Array: `[:name, "Tuile::Size", [args]]`, `[:optional, node]`,
    # `[:union, [nodes]]`, `[:literal, value]`, `[:bool]`, `[:nil]` — the same nodes
    # `RBSTypes` builds from the `rbs` gem's AST, so both strategies share one builder.
    #
    # @api private
    class TypeParser
      TOKEN = /\s*(?:(::)|([A-Za-z_]\w*)|("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')|(-?\d+(?:\.\d+)?)|([\[\],|?()]))/
      private_constant :TOKEN

      # @param source [String] the type as written, `"Array[String]?"`
      # @return [Array] the syntax tree
      # @raise [DefinitionError] on a syntax error
      def self.parse(source)
        new(source).parse
      end

      # @param source [String]
      def initialize(source)
        @source = source
        @tokens = tokenize(source)
        @pos = 0
      end

      # @return [Array] the syntax tree
      # @raise [DefinitionError] on a syntax error
      def parse
        node = union
        fail_at("unexpected #{peek.inspect}") if peek
        node
      end

      private

      def tokenize(source)
        tokens = []
        rest = source
        until rest.strip.empty?
          match = TOKEN.match(rest)
          unless match&.begin(0)&.zero?
            raise DefinitionError,
                  "type #{source.inspect}: cannot read #{rest.strip.inspect}"
          end

          tokens << match.captures.compact.first
          rest = match.post_match
        end
        tokens
      end

      def peek = @tokens[@pos]

      def take
        @tokens[@pos].tap { @pos += 1 }
      end

      def expect(token)
        fail_at("expected #{token.inspect}, got #{peek.inspect}") unless peek == token
        take
      end

      def fail_at(detail)
        raise DefinitionError, "type #{@source.inspect}: #{detail}"
      end

      def union
        members = [postfix]
        while peek == "|"
          take
          members << postfix
        end
        members.size == 1 ? members.first : [:union, members]
      end

      def postfix
        node = primary
        while peek == "?"
          take
          node = [:optional, node] unless node.first == :optional
        end
        node
      end

      def primary
        token = peek
        fail_at("unexpected end") if token.nil?
        return parenthesized if token == "("
        return [:literal, literal(take)] if token.match?(/\A(?:["'-]|\d)/)

        case token
        when "bool" then take && [:bool]
        when "nil" then take && [:nil]
        when "true" then take && [:literal, true]
        when "false" then take && [:literal, false]
        else name
        end
      end

      def parenthesized
        expect("(")
        node = union
        expect(")")
        node
      end

      def literal(token)
        case token
        when /\A"/ then token[1..-2].gsub(/\\(.)/, '\1')
        when /\A'/ then token[1..-2].gsub(/\\(.)/, '\1')
        when /\./ then fail_at("a Float literal is not a type in RBS: #{token}")
        else Integer(token)
        end
      end

      def name
        parts = []
        absolute = peek == "::"
        take if absolute
        loop do
          part = take
          fail_at("expected a constant, got #{part.inspect}") unless part&.match?(/\A[A-Z]/)
          parts << part
          break unless peek == "::"

          take
        end
        [:name, "#{"::" if absolute}#{parts.join("::")}", arguments]
      end

      def arguments
        return [] unless peek == "["

        take
        args = [union]
        while peek == ","
          take
          args << union
        end
        expect("]")
        args
      end
    end
  end
end
