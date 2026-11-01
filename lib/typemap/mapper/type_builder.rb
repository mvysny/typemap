# frozen_string_literal: true

module Typemap
  class Mapper
    # Turns a type syntax tree (see {TypeParser}) into the {Type} the mapper checks, resolving
    # constant names from the declaring namespace. Both type strategies end here, so they accept
    # exactly the same subset; anything outside it raises "unsupported type".
    #
    # @api private
    module TypeBuilder
      # @param node [Array] the syntax tree
      # @param namespace [String, nil] the declaring class's full name, for relative names
      # @return [Object] a {Type}
      # @raise [DefinitionError] on an unsupported type or an unknown constant
      def self.build(node, namespace)
        case node.first
        when :optional then optional(build(node[1], namespace))
        when :union then union(node[1], namespace)
        when :literal then literals([node[1]])
        when :bool then Type::Bool.new
        when :nil then unsupported("nil alone")
        when :name then named(node[1], node[2], namespace)
        else raise ArgumentError, "not a type node: #{node.inspect}"
        end
      end

      # @param inner [Object] a {Type}
      # @return [Type::Optional]
      def self.optional(inner)
        inner.is_a?(Type::Optional) ? inner : Type::Optional.new(inner: inner)
      end

      # `"a" | "b"`, optionally with `nil` among them; a union of anything but literals is
      # outside the subset.
      def self.union(members, namespace)
        nilable = members.any? { |member| member.first == :nil }
        rest = members.reject { |member| member.first == :nil }
        unsupported("a union of #{rest.size} types besides nil") if rest.empty?
        built = rest.size == 1 ? build(rest.first, namespace) : literals(rest.map { |member| literal_value(member) })
        nilable ? optional(built) : built
      end

      def self.literal_value(node)
        unsupported("a union of anything but literals: #{node.inspect}") unless node.first == :literal
        node[1]
      end

      def self.literals(values)
        values.each do |value|
          supported = [String, Integer, TrueClass, FalseClass].any? { |klass| value.is_a?(klass) }
          unsupported("the literal #{value.inspect}: a file cannot hold one") unless supported
        end
        Type::Literals.new(values: values)
      end

      def self.named(name, args, namespace)
        constant = NameResolver.resolve(name, namespace)
        if [Integer, Float, String].include?(constant)
          unsupported("#{name}[…]") unless args.empty?
          Type::Scalar.new(klass: constant)
        elsif constant == Array
          unsupported("Array without exactly one element type") unless args.size == 1
          Type::ArrayOf.new(element: build(args.first, namespace))
        elsif constant == Hash
          hash_of(args, namespace)
        elsif constant.is_a?(Class) && args.empty?
          Type::ClassRef.new(klass: constant)
        else
          unsupported(args.empty? ? name : "#{name}[…]")
        end
      end

      def self.hash_of(args, namespace)
        unsupported("Hash without a key and a value type") unless args.size == 2
        key = build(args.first, namespace)
        unsupported("Hash[#{key}, …]: a key is always a String") unless key == Type::Scalar.new(klass: String)
        Type::HashOf.new(value: build(args.last, namespace))
      end

      private_class_method :union, :literal_value, :literals, :named, :hash_of

      # @raise [DefinitionError] always
      def self.unsupported(what)
        raise DefinitionError, "unsupported type: #{what}"
      end
    end
  end
end
