# frozen_string_literal: true

RSpec.describe Typemap::Mapper::Type do
  let(:mapper) { Typemap::Mapper.new }

  def load_value(type, value, default: nil, **limits)
    klass = Holder.of(type, default, **limits)
    mapper.load(klass, { "value" => value }).value
  end

  def error_for(type, value, default: nil, **limits)
    assert_raises(Typemap::DataError) { load_value(type, value, default: default, **limits) }.message
  end

  describe "Integer" do
    it("takes an Integer") { assert_equal 70, load_value("Integer", 70, default: 1) }
    it("rejects a String") { assert_equal 'value: expected Integer, got "70"', error_for("Integer", "70", default: 1) }
    it("rejects 70.0") { assert_equal "value: expected Integer, got 70.0", error_for("Integer", 70.0, default: 1) }
    it("rejects nil") { assert_equal "value: expected Integer, got nil", error_for("Integer", nil, default: 1) }
  end

  describe "Float" do
    it("takes a Float") { assert_equal 0.5, load_value("Float", 0.5, default: 1.0) }
    it("rejects an Integer, uncoerced") {
      assert_equal "value: expected Float, got 1", error_for("Float", 1, default: 1.0)
    }
  end

  describe "String" do
    it("takes a String") { assert_equal "a", load_value("String", "a", default: "") }
    it("rejects a Symbol") { assert_equal "value: expected String, got :a", error_for("String", :a, default: "") }
    it "checks format:" do
      assert_equal 'value: "ab" does not match /\A[a-z]\z/',
                   error_for("String", "ab", default: "a", format: /\A[a-z]\z/)
    end
    it "checks in: as a list" do
      assert_equal 'value: "c" is not one of ["a", "b"]', error_for("String", "c", default: "a", in: %w[a b])
    end
  end

  describe "bool" do
    it("takes false") { assert_equal false, load_value("bool", false, default: true) }
    it("rejects 0") { assert_equal "value: expected bool, got 0", error_for("bool", 0, default: true) }
  end

  describe "T?" do
    it("takes nil") { assert_nil load_value("Integer?", nil, default: 1) }
    it("takes a T") { assert_equal 2, load_value("Integer?", 2) }
    it("never limits nil") { assert_nil load_value("Integer?", nil, in: 1..3) }
    it("still limits a T") { assert_equal "value: 5 is not in 1..3", error_for("Integer?", 5, in: 1..3) }
  end

  describe "literal unions" do
    it("take a listed value") { assert_equal "verbose", load_value('"short" | "verbose"', "verbose", default: "short") }
    it "reject anything else" do
      assert_equal 'value: expected "short" | "verbose", got "long"',
                   error_for('"short" | "verbose"', "long", default: "short")
    end
    it("tell 1 from 1.0") { assert_equal "value: expected 1 | 2, got 1.0", error_for("1 | 2", 1.0, default: 1) }
    it("take nil when nil is among them") { assert_nil load_value('"a" | "b" | nil', nil) }
  end

  describe "Array[T]" do
    it("takes an Array of T") { assert_equal %w[a b], load_value("Array[String]", %w[a b], default: []) }
    it "names the bad element by index" do
      assert_equal "value[1]: expected String, got 2", error_for("Array[String]", ["a", 2], default: [])
    end
    it("rejects a Hash") {
      assert_equal "value: expected Array[String], got {}", error_for("Array[String]", {}, default: [])
    }
  end

  describe "Hash[String, T]" do
    it "takes a table, Symbol keys as Strings" do
      assert_equal({ "a" => 1 }, load_value("Hash[String, Integer]", { a: 1 }, default: {}))
    end
    it "names the bad value by key" do
      assert_equal 'value.b: expected Integer, got "x"', error_for("Hash[String, Integer]", { "b" => "x" }, default: {})
    end
    it "rejects a key that is neither String nor Symbol" do
      assert_equal "value: key 1 is not a String", error_for("Hash[String, Integer]", { 1 => 1 }, default: {})
    end
  end
end
