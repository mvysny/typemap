# frozen_string_literal: true

module Typemap
  class Mapper
    # Resolves a constant name written in a type — `Integer`, `Size`, `Tuile::Size`, `::Size` —
    # the way Ruby resolves it in the code beside it: a leading `::` is absolute, anything else is
    # looked up from the declaring namespace outward (`UI::Foo::Size`, then `UI::Size`, then
    # `Size`). Qualified names are allowed, never required. Inheritance is not searched, only the
    # lexical scopes.
    #
    # @api private
    module NameResolver
      # @param name [String] the name as written, `"Size"`, `"Tuile::Size"`, `"::Size"`
      # @param namespace [String, nil] the declaring class's full name, `nil` for the top level
      # @return [Module] the constant
      # @raise [DefinitionError] if no scope defines it
      def self.resolve(name, namespace)
        return lookup(Object, name.delete_prefix("::")) || unknown(name) if name.start_with?("::")

        scopes = namespace.to_s.split("::")
        scopes.length.downto(0) do |depth|
          base = depth.zero? ? Object : lookup(Object, scopes.first(depth).join("::"))
          found = base && lookup(base, name)
          return found if found
        end
        unknown(name)
      end

      # @param base [Module]
      # @param path [String] `"A::B"`, looked up segment by segment without inheritance
      # @return [Module, nil]
      def self.lookup(base, path)
        path.split("::").reduce(base) do |mod, segment|
          return nil unless mod.is_a?(Module) && mod.const_defined?(segment, false)

          mod.const_get(segment, false)
        end
      end

      # @raise [DefinitionError]
      def self.unknown(name)
        raise DefinitionError, "unknown constant #{name}"
      end
    end
  end
end
