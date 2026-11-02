# frozen_string_literal: true

module ConstrainSpec
  class Base
    extend Typemap::Constrain

    attr_accessor :a, :b

    constrain :a, type: "Integer"
    constrain :a, in: 1..5
    constrain :b, type: "String"

    def initialize
      @a = 1
      @b = ""
    end
  end

  class Child < Base
    constrain :b, format: /x/
  end
end

RSpec.describe Typemap::Constrain do
  def klass = Class.new { extend Typemap::Constrain }

  it "merges several calls for one property" do
    constraint = Typemap::Constrain.constraints_for(ConstrainSpec::Base)[:a]
    assert_equal "Integer", constraint.type
    assert_equal 1..5, constraint.in
    assert_equal ConstrainSpec::Base, constraint.type_owner
  end

  it "inherits a superclass's constraints and adds to them" do
    constraint = Typemap::Constrain.constraints_for(ConstrainSpec::Child)[:b]
    assert_equal "String", constraint.type
    assert_equal(/x/, constraint.format)
  end

  it "rejects an option given twice for one property" do
    error = assert_raises(ArgumentError) do
      klass.tap do |k|
        k.constrain(:a, type: "Integer")
      end.constrain(:a, type: "String")
    end
    assert_equal "constrain :a: type: given twice", error.message
  end

  it "rejects an unknown option the moment the class body runs" do
    assert_raises(ArgumentError) { klass.constrain(:a, in_: 1..2) }
  end

  it "rejects a Ruby class as type:" do
    assert_raises(ArgumentError) { klass.constrain(:a, type: Integer) }
  end

  it "takes not_blank: and not_empty: only as true" do
    error = assert_raises(ArgumentError) { klass.constrain(:a, not_blank: false) }
    assert_equal "constrain: not_blank: must be true, or left out, got false", error.message
    assert_raises(ArgumentError) { klass.constrain(:a, not_empty: 1) }
  end

  it "takes unique: only as true, unique_by: only as a Symbol or a Proc, and not both" do
    assert_raises(ArgumentError) { klass.constrain(:a, unique: false) }
    error = assert_raises(ArgumentError) { klass.constrain(:a, unique_by: "id") }
    assert_equal 'constrain: unique_by: must be a Symbol or a Proc, got "id"', error.message
    error = assert_raises(ArgumentError) { klass.constrain(:a, unique: true, unique_by: :id) }
    assert_equal "constrain: unique: and unique_by: together; unique_by: alone says what to compare", error.message
    klass.constrain(:a, unique_by: ->(entry) { entry })
  end

  it "rejects a call with nothing to record" do
    assert_raises(ArgumentError) { klass.constrain(:a) }
  end

  it "inherits a superclass's unknown policy, which a subclass may replace" do
    base = klass.tap { |k| k.unknown(:ignore) }
    assert_equal :ignore, Typemap::Constrain.unknown_for(Class.new(base))
    assert_equal :raise, Typemap::Constrain.unknown_for(Class.new(base).tap { |k| k.unknown(:raise) })
    assert_nil Typemap::Constrain.unknown_for(klass)
  end

  it "takes unknown only as :raise or :ignore, and once per class" do
    error = assert_raises(ArgumentError) { klass.unknown(:warn) }
    assert_equal "unknown: must be :raise or :ignore, got :warn", error.message
    error = assert_raises(ArgumentError) { klass.tap { |k| k.unknown(:ignore) }.unknown(:raise) }
    assert_equal "unknown: given twice", error.message
  end

  it "rejects a name that is not a Symbol" do
    assert_raises(ArgumentError) { klass.constrain("a", type: "Integer") }
    assert_raises(ArgumentError) { klass.ignore("a") }
  end
end
