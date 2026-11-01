# frozen_string_literal: true

module Confect
  class Mapper
    # The default type strategy, needing no gem: every property's type comes from
    # `constrain type:`, parsed by Confect's own {TypeParser}. A property without one raises —
    # a type is never read off the default (`D_types_declared`).
    class BasicTypes
      # @param klass [Class] the class being read
      # @param name [Symbol] the property
      # @param constraint [Constrain::Constraint, nil] what `constrain` recorded for it
      # @return [Object] the property's {Type}
      # @raise [DefinitionError] when `constrain` gave no type, or the type is unsupported
      def type_for(klass, name, constraint)
        unless constraint&.type
          raise DefinitionError, "no type: give it `constrain :#{name}, type: \"…\"` " \
                                 "(#{klass} uses Confect::Constrain), or map it with Confect::Mapper::RBSTypes"
        end

        TypeBuilder.build(TypeParser.parse(constraint.type), constraint.type_owner.name)
      end
    end
  end
end
