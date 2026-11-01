# frozen_string_literal: true

module Typemap
  class Mapper
    # The shape of a data class (`Data.define`): its properties are its `members`, in order, and
    # an instance is built in one `new(**values)`. A keyword without a default is a required key:
    #
    #     Llm = Data.define(:api_key, :model) do
    #       def initialize(api_key:, model: "gpt-5") = super   # api_key required, model not
    #     end
    #
    # @api private
    module DataShape
      READABLE = %i[key keyreq].freeze
      private_constant :READABLE

      # @param klass [Class] a `Data` subclass
      # @return [Array<Symbol>] its members, in declaration order
      def self.properties(klass) = klass.members

      # The keywords `klass.new` cannot build without, read off `initialize`: every member when
      # `Data`'s own `initialize` is left as is, else its `name:` keywords.
      #
      # @param klass [Class] a `Data` subclass
      # @param names [Array<Symbol>] the mapped members, `ignore`d ones left out
      # @return [Array<Symbol>]
      # @raise [DefinitionError] on an `initialize` taking anything but `name:` / `name: default`
      #   keywords, one with no keyword for a member, or one requiring a keyword the file cannot give
      def self.required_keywords(klass, names)
        init = klass.instance_method(:initialize)
        return unmapped_checked(klass, klass.members, names) if init.owner == Data

        params = init.parameters
        unless params.all? { |kind, _| READABLE.include?(kind) }
          raise DefinitionError, "#{klass}#initialize takes #{params.inspect}; Typemap reads which keys are " \
                                 "required only from `name:` and `name: default` keywords"
        end
        missing = klass.members - params.map(&:last)
        raise DefinitionError, "#{klass}#initialize takes no keyword #{missing.join(", ")}" unless missing.empty?

        unmapped_checked(klass, params.filter_map { |kind, name| name if kind == :keyreq }, names)
      end

      # @param klass [Class]
      # @param names [Array<Symbol>] the properties `constrain` gave `required:`
      # @return [void]
      # @raise [DefinitionError] unless `names` is empty: a data class's keyword without a default
      #   is how it says "required"
      def self.check_required_option(klass, names)
        return if names.empty?

        raise DefinitionError, "#{klass}##{names.first}: required: is for an accessor class; " \
                               "in a data class, a keyword without a default is required"
      end

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

      # @return [Array<Symbol>] `required`
      # @raise [DefinitionError] if one of them is not mapped, so no file can give it
      def self.unmapped_checked(klass, required, names)
        unmapped = required - names
        return required if unmapped.empty?

        raise DefinitionError, "#{klass}#initialize requires #{unmapped.join(", ")}, not a mapped property, " \
                               "so no file can give it"
      end
      private_class_method :unmapped_checked
    end
  end
end
