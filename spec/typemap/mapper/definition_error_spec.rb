# frozen_string_literal: true

module DefinitionErrorSpec
  class Untyped
    attr_accessor :a

    def initialize = @a = 1
  end

  class NeedsArguments
    extend Typemap::Constrain

    attr_accessor :a

    constrain :a, type: "Integer"

    def initialize(value) = @a = value
  end

  class NoProperties
    def initialize; end
  end

  class StrayConstrain
    extend Typemap::Constrain

    attr_accessor :a

    constrain :a, type: "Integer"
    constrain :b, type: "Integer"

    def initialize = @a = 1
  end

  class StrayIgnore
    extend Typemap::Constrain

    attr_accessor :a

    constrain :a, type: "Integer"
    ignore :b

    def initialize = @a = 1
  end

  class Unsupported
    extend Typemap::Constrain

    attr_accessor :a

    constrain :a, type: "Set[String]"

    def initialize = @a = nil
  end

  class Nested
    extend Typemap::Constrain

    attr_accessor :inner

    constrain :inner, type: "Untyped"

    def initialize = @inner = Untyped.new
  end

  # A class nested in itself: planning must terminate.
  class Tree
    extend Typemap::Constrain

    attr_accessor :children

    constrain :children, type: "Array[Tree]"

    def initialize = @children = []
  end
end

RSpec.describe Typemap::Mapper, "reading a class it cannot map" do
  let(:mapper) { Typemap::Mapper.new }

  def error_for(klass)
    assert_raises(Typemap::DefinitionError) { mapper.load(klass, {}) }.message
  end

  def holder(type, default, **limits) = Holder.of(type, default, **limits)

  it "raises on a property with no type, naming the fix" do
    assert_match(/\ADefinitionErrorSpec::Untyped#a: no type: give it `constrain :a, type: "…"`/,
                 error_for(DefinitionErrorSpec::Untyped))
  end

  it "raises on a class new cannot build bare" do
    assert_match(/NeedsArguments: must build with a bare new/, error_for(DefinitionErrorSpec::NeedsArguments))
  end

  it "raises on a class with no properties" do
    assert_match(/NoProperties has no properties/, error_for(DefinitionErrorSpec::NoProperties))
  end

  it "raises on constrain naming no property" do
    assert_match(/StrayConstrain: constrain names b, not a property/, error_for(DefinitionErrorSpec::StrayConstrain))
  end

  it "raises on ignore naming no property" do
    assert_match(/StrayIgnore: ignore names b, not a property/, error_for(DefinitionErrorSpec::StrayIgnore))
  end

  it "raises on a type outside the subset" do
    assert_match(/Unsupported#a: unsupported type: Set\[…\]/, error_for(DefinitionErrorSpec::Unsupported))
  end

  it "raises on a default the type rejects" do
    assert_match(/value: its default nil does not fit Integer/, error_for(holder("Integer", nil)))
  end

  it "raises on a default outside the limits" do
    assert_match(/value: its default must be 1 to 3, got 0/, error_for(holder("Integer", 0, in: 1..3)))
  end

  it "raises on a limit the type cannot take" do
    assert_match(/format: .* limits only a String, not Integer/, error_for(holder("Integer", 1, format: /x/)))
    assert_match(/in: 1..3 cannot limit bool/, error_for(holder("bool", true, in: 1..3)))
    assert_match(/is a range, so it limits only a number with number ends, not String/,
                 error_for(holder("String", "a", in: "a".."z")))
  end

  it "points not_empty: on a String to not_blank:, and back" do
    assert_match(/not_empty: limits only an Array or a Hash, not String\?; a String takes not_blank:/,
                 error_for(holder("String?", nil, not_empty: true)))
    assert_match(/not_blank: limits only a String, not Array\[String\]; an Array or a Hash takes not_empty:/,
                 error_for(holder("Array[String]", [], not_blank: true)))
    assert_match(/not_blank: limits only a String, not Integer\z/, error_for(holder("Integer", 1, not_blank: true)))
  end

  it "raises on a blank default under not_blank:" do
    assert_match(/value: its default must not be blank/, error_for(holder("String", "", not_blank: true)))
  end

  it "raises for a nested class's problem when the outer class is first read" do
    assert_match(/Untyped#a: no type/, error_for(DefinitionErrorSpec::Nested))
  end

  it "raises before reading the file at all" do
    assert_raises(Typemap::DefinitionError) { mapper.load(DefinitionErrorSpec::Untyped, { "a" => 1 }) }
  end

  it "plans a class nested in itself" do
    tree = mapper.load(DefinitionErrorSpec::Tree, { "children" => [{ "children" => [] }] })
    assert_equal 1, tree.children.size
  end
end
