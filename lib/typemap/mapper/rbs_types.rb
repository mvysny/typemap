# frozen_string_literal: true

module Typemap
  class Mapper
    # The type strategy for a project that keeps `sig/*.rbs` — written by hand, or by sord from
    # YARD tags. A property's type is its reader's in the signature files: an `attr_reader` /
    # `attr_accessor`, or a zero-argument `def name: () -> T`, found along the class's ancestors.
    # `constrain type:` is still allowed for a property the signatures do not cover, but never
    # for one they do — a type declared twice drifts (`D_types_declared`).
    #
    # Needs the `rbs` gem, the app's dependency and never Typemap's; only its parser is used,
    # not its type environment (`R_rbs_parser`), and not a reader of our own (`D_rbs_gem_parser`).
    class RBSTypes
      # @param sig [Array<String>, nil] the `.rbs` files, or directories searched for them; `nil`
      #   finds the `sig/` directory beside each class's own source, walking up from its file
      # @raise [LoadError] if the `rbs` gem cannot be loaded
      def initialize(sig: nil)
        begin
          require "rbs"
        rescue ::LoadError => e
          raise ::LoadError,
                "Typemap::Mapper::RBSTypes needs the rbs gem: add `gem \"rbs\"` to the Gemfile (#{e.message})"
        end
        @sig = sig&.then { |paths| expand(paths) }
        @indexes = {}
        @lock = Mutex.new
      end

      # @param klass [Class] the class being read
      # @param name [Symbol] the property
      # @param constraint [Constrain::Constraint, nil] what `constrain` recorded for it
      # @return [Object] the property's {Type}
      # @raise [DefinitionError] when neither the signatures nor `constrain` give a type, when
      #   both do, or the type is unsupported
      def type_for(klass, name, constraint)
        found = signature_type(klass, name)
        if found && constraint&.type
          raise DefinitionError, "type declared twice: in #{found[:where]} and by `constrain type:`; keep one"
        end
        return TypeBuilder.build(parse_type(constraint.type), constraint.type_owner.name) if constraint&.type

        unless found
          raise DefinitionError, "no type: #{klass}##{name} has no reader in #{files_for(klass).join(", ")}, " \
                                 "and no `constrain :#{name}, type: \"…\"`"
        end

        build(found, name)
      end

      # A `constrain type:` string through the `rbs` gem's own parser, as a {TypeParser} tree.
      #
      # @param source [String]
      # @return [Array]
      # @raise [DefinitionError] on a syntax error or an unsupported type
      def parse_type(source)
        parsed = ::RBS::Parser.parse_type(source)
        raise DefinitionError, "type #{source.inspect}: empty" unless parsed

        tree(parsed)
      rescue ::RBS::ParsingError => e
        raise DefinitionError, "type #{source.inspect}: #{e.message}"
      end

      private

      def build(found, name)
        TypeBuilder.build(tree(found[:type]), found[:namespace])
      rescue DefinitionError => e
        raise DefinitionError, "#{e.message} (#{name} at #{found[:where]})"
      end

      # @return [Hash, nil] `{type:, namespace:, where:}` of the first ancestor whose signature
      #   declares a reader for `name`
      def signature_type(klass, name)
        index = index_for(files_for(klass))
        klass.ancestors.each do |mod|
          next if mod.name.nil?

          hits = (index[mod.name] || []).flat_map { |decl| readers(decl, name) }
          next if hits.empty?

          if hits.map { |hit| hit[:type].to_s }.uniq.size > 1
            raise DefinitionError, "type declared twice: #{hits.map { |hit| hit[:where] }.join(" and ")}"
          end

          return hits.first.merge(namespace: mod.name)
        end
        nil
      end

      def readers(decl, name)
        decl.members.filter_map do |member|
          type = reader_type(member, name)
          next unless type

          location = member.location
          { type: type, where: "#{location&.buffer&.name}:#{location&.start_line}" }
        end
      end

      def reader_type(member, name)
        case member
        when ::RBS::AST::Members::AttrReader, ::RBS::AST::Members::AttrAccessor
          member.type if member.name == name
        when ::RBS::AST::Members::MethodDefinition
          return unless member.name == name && member.kind == :instance

          function = member.overloads.first.method_type.type
          function.return_type if function.respond_to?(:required_positionals) && function.required_positionals.empty?
        end
      end

      # The `rbs` gem's type AST, translated to {TypeParser}'s tree.
      def tree(type)
        case type
        when ::RBS::Types::ClassInstance then [:name, type.name.to_s, type.args.map { |arg| tree(arg) }]
        when ::RBS::Types::Optional then [:optional, tree(type.type)]
        when ::RBS::Types::Union then [:union, type.types.map { |member| tree(member) }]
        when ::RBS::Types::Literal then [:literal, type.literal]
        when ::RBS::Types::Bases::Bool then [:bool]
        when ::RBS::Types::Bases::Nil then [:nil]
        when ::RBS::Types::Bases::Any then [:untyped]
        else TypeBuilder.unsupported(type.to_s)
        end
      end

      def files_for(klass)
        return @sig if @sig

        source = klass.name && Module.const_source_location(klass.name)&.first
        unless source
          raise DefinitionError,
                "#{klass.inspect}: no source file to find sig/ from; pass RBSTypes.new(sig: [...])"
        end

        dir = File.dirname(File.expand_path(source))
        until File.directory?(File.join(dir, "sig"))
          parent = File.dirname(dir)
          raise DefinitionError, "#{klass}: no sig/ directory above #{source}" if parent == dir

          dir = parent
        end
        expand([File.join(dir, "sig")])
      end

      def expand(paths)
        paths.flat_map { |path| File.directory?(path) ? Dir.glob(File.join(path, "**", "*.rbs")) : [path] }.sort
      end

      def index_for(files)
        @lock.synchronize { @indexes[files] ||= files.each_with_object({}) { |file, index| add_file(file, index) } }
      end

      def add_file(file, index)
        buffer = ::RBS::Buffer.new(name: file, content: File.read(file))
        _, _, decls = ::RBS::Parser.parse_signature(buffer)
        add_decls(decls, [], index)
      rescue ::RBS::ParsingError => e
        raise DefinitionError, "#{file}: #{e.message}"
      end

      def add_decls(decls, namespace, index)
        decls.each do |decl|
          next unless decl.is_a?(::RBS::AST::Declarations::Class) || decl.is_a?(::RBS::AST::Declarations::Module)

          written = decl.name.to_s
          full = written.start_with?("::") ? written.delete_prefix("::").split("::") : namespace + written.split("::")
          (index[full.join("::")] ||= []) << decl
          add_decls(decl.members, full, index)
        end
      end
    end
  end
end
