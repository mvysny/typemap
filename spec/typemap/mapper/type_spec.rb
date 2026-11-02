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
    it "rejects a String, telling to remove the quotes" do
      assert_equal 'value: expected Integer, got "70"; remove the quotes', error_for("Integer", "70", default: 1)
    end
    it("takes 70.0 as 70") { assert_same 70, load_value("Integer", 70.0, default: 1) }
    it("rejects 70.5") { assert_equal "value: expected Integer, got 70.5", error_for("Integer", 70.5, default: 1) }
    it("rejects NaN") { assert_equal "value: expected Integer, got NaN", error_for("Integer", Float::NAN, default: 1) }
    it("rejects Infinity") {
      assert_equal "value: expected Integer, got Infinity", error_for("Integer", Float::INFINITY, default: 1)
    }
    it("limits 70.0 as 70") {
      assert_equal "value: must be 1 to 3, got 70", error_for("Integer", 70.0, default: 1, in: 1..3)
    }
    it("rejects nil") { assert_equal "value: expected Integer, got nil", error_for("Integer", nil, default: 1) }
    it("keeps a default strict") {
      error = assert_raises(Typemap::DefinitionError) { load_value("Integer", 1, default: 1.0) }
      assert_match(/its default 1.0 does not fit Integer/, error.message)
    }
  end

  describe "Float" do
    it("takes a Float") { assert_equal 0.5, load_value("Float", 0.5, default: 1.0) }
    it "takes 5 as 5.0" do
      value = load_value("Float", 5, default: 1.0)
      assert_equal 5.0, value
      assert_kind_of Float, value
    end
    it("takes 5 in a Float?") { assert_kind_of Float, load_value("Float?", 5) }
    it("rejects an Integer a Float would round") {
      assert_equal "value: expected Float, got 9007199254740993", error_for("Float", (2**53) + 1, default: 1.0)
    }
    it("rejects an Integer beyond a Float") {
      assert_match(/expected Float/, error_for("Float", 10**400, default: 1.0))
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
      assert_equal 'value: must be one of "a", "b", got "c"', error_for("String", "c", default: "a", in: %w[a b])
    end
  end

  describe "in: as a range, in words" do
    it("1..3") { assert_equal "value: must be 1 to 3, got 4", error_for("Integer", 4, default: 1, in: 1..3) }
    it("1..") { assert_equal "value: must be at least 1, got 0", error_for("Integer", 0, default: 1, in: 1..) }
    it("..3") { assert_equal "value: must be at most 3, got 4", error_for("Integer", 4, default: 1, in: ..3) }
    it("...3") { assert_equal "value: must be below 3, got 3", error_for("Integer", 3, default: 1, in: ...3) }
    it("1...3") {
      assert_equal "value: must be at least 1 and below 3, got 3", error_for("Integer", 3, default: 1, in: 1...3)
    }
    it("0.0..1.0") {
      assert_equal "value: must be 0.0 to 1.0, got 1.5", error_for("Float", 1.5, default: 0.5, in: 0.0..1.0)
    }
  end

  describe "bool" do
    it("takes false") { assert_equal false, load_value("bool", false, default: true) }
    it("rejects 0") { assert_equal "value: expected bool, got 0", error_for("bool", 0, default: true) }
  end

  describe "T?" do
    it("takes nil") { assert_nil load_value("Integer?", nil, default: 1) }
    it("takes a T") { assert_equal 2, load_value("Integer?", 2) }
    it("never limits nil") { assert_nil load_value("Integer?", nil, in: 1..3) }
    it("still limits a T") { assert_equal "value: must be 1 to 3, got 5", error_for("Integer?", 5, in: 1..3) }
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
      assert_equal "value[1]: expected String, got 2; quote it to make it a string",
                   error_for("Array[String]", ["a", 2], default: [])
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

  describe "Object" do
    params = { "kwargs" => { "enable_thinking" => false, "stop" => nil }, "n" => [1, 2.5, "x"] }

    it("passes plain data through") { assert_equal params, load_value("Object", params, default: {}) }
    it("keeps 5 an Integer") { assert_same 5, load_value("Hash[String, Object]", { "n" => 5 }, default: {})["n"] }
    it "takes Symbol keys as Strings, all the way down" do
      assert_equal({ "a" => [{ "b" => 1 }] }, load_value("Object", { a: [{ b: 1 }] }, default: {}))
    end
    it "loads new containers" do
      raw = { "a" => [1] }
      refute_same raw["a"], load_value("Object", raw, default: {})["a"]
    end
    it "rejects a value no type loads, with its path" do
      assert_equal "value.a[1]: expected plain data (String, Integer, Float, bool, nil, Array or Hash), got :x",
                   error_for("Object", { "a" => [1, :x] }, default: {})
    end
    it "rejects a key neither String nor Symbol" do
      assert_equal "value.a: key true is not a String", error_for("Object", { "a" => { true => 1 } }, default: {})
    end
    it "rejects nil in its own place" do
      assert_equal "value: expected Object, got nil", error_for("Object", nil, default: 1)
    end
    it("takes nil when written Object?") { assert_nil load_value("Object?", nil) }
    it "checks a Hash[String, Object]'s outer level" do
      assert_equal "value: expected Hash[String, Object], got 7", error_for("Hash[String, Object]", 7, default: {})
    end
    it "rejects a nil value of a Hash[String, Object]" do
      assert_equal "value.a: expected Object, got nil", error_for("Hash[String, Object]", { "a" => nil }, default: {})
    end
    it "rejects a default with a Symbol key" do
      error = assert_raises(Typemap::DefinitionError) { load_value("Object", {}, default: { a: 1 }) }
      assert_match(/value: its default .* does not fit Object/, error.message)
    end
    it "rejects a Proc on dump" do
      holder = Holder.of("Hash[String, Object]", {}).new
      holder.value = { "f" => -> {} }
      error = assert_raises(Typemap::DataError) { mapper.dump(holder) }
      assert_match(/\Avalue\.f: expected plain data .*, got #<Proc/, error.message)
    end
    it "dumps Symbol keys as Strings" do
      holder = Holder.of("Object", {}).new
      holder.value = { a: { b: [nil] } }
      assert_equal({ "value" => { "a" => { "b" => [nil] } } }, mapper.dump(holder))
    end
  end
end
