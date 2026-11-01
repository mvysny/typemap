# frozen_string_literal: true

module NameResolverSpec
  Size = Class.new

  module Inner
    Size = Class.new

    class Deep; end
  end
end

RSpec.describe Confect::Mapper::NameResolver do
  def resolve(name, namespace) = Confect::Mapper::NameResolver.resolve(name, namespace)

  it "finds a relative name in the innermost scope first" do
    assert_same NameResolverSpec::Inner::Size, resolve("Size", "NameResolverSpec::Inner::Deep")
  end

  it "walks outward" do
    assert_same NameResolverSpec::Size, resolve("Size", "NameResolverSpec::Other")
  end

  it "takes a qualified name" do
    assert_same NameResolverSpec::Size, resolve("NameResolverSpec::Size", "NameResolverSpec::Inner")
  end

  it "takes a leading :: as absolute" do
    assert_same Integer, resolve("::Integer", "NameResolverSpec::Inner")
  end

  it "finds the top level from no namespace" do
    assert_same String, resolve("String", nil)
  end

  it "searches scopes, not ancestors" do
    assert_raises(Confect::DefinitionError) { resolve("Comparable::Size", nil) }
  end

  it "raises on an unknown name" do
    error = assert_raises(Confect::DefinitionError) { resolve("Nope", "NameResolverSpec") }
    assert_equal "unknown constant Nope", error.message
  end
end
