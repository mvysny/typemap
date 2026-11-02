# frozen_string_literal: true

module ValidationSpec
  class Range < Data.define(:low, :high)
    extend Typemap::Constrain

    constrain :low, :high, type: "Integer", in: 0..100

    def initialize(low: 0, high: 100) = super

    def validate
      raise "low must not be above high" if low > high
    end
  end

  class Ranges < Data.define(:list, :named)
    extend Typemap::Constrain

    constrain :list, type: "Array[Range]"
    constrain :named, type: "Hash[String, Range?]"

    def initialize(list: [], named: {}) = super

    def validate
      raise "outer" if list.size > 2
    end
  end

  # Its default breaks its own validate: only a load reveals it, the class read never calls validate.
  class Inverted
    extend Typemap::Constrain

    attr_accessor :range

    constrain :range, type: "Range"

    def initialize = @range = Range.new(low: 9, high: 1)
  end
end

RSpec.describe Typemap::Mapper, "validating the result" do
  let(:mapper) { Typemap::Mapper.new }

  def range(low, high) = ValidationSpec::Range.new(low: low, high: high)

  describe "#load" do
    it "validates a nested object the file leaves out" do
      error = assert_raises(Typemap::DataError) { mapper.load(ValidationSpec::Inverted, {}) }
      assert_equal "range: low must not be above high", error.message
    end

    it "reaches objects in an Array and a Hash, with their paths" do
      error = assert_raises(Typemap::DataError) do
        mapper.load(ValidationSpec::Ranges, { "list" => [{}, { "low" => 7, "high" => 3 }] })
      end
      assert_equal "list[1]: low must not be above high", error.message
      error = assert_raises(Typemap::DataError) do
        mapper.load(ValidationSpec::Ranges, { "named" => { "a" => nil, "b" => { "high" => 101 } } })
      end
      assert_equal "named.b.high: must be 0 to 100, got 101", error.message
    end

    it "validates nested objects first" do
      error = assert_raises(Typemap::DataError) do
        mapper.load(ValidationSpec::Ranges, { "list" => [{}, {}, { "low" => 7, "high" => 3 }] })
      end
      assert_equal "list[2]: low must not be above high", error.message
    end
  end

  describe "#dump" do
    it "raises on a value outside its limits" do
      error = assert_raises(Typemap::DataError) { mapper.dump(range(0, 170)) }
      assert_equal "high: must be 0 to 100, got 170", error.message
    end

    it "calls validate" do
      error = assert_raises(Typemap::DataError) { mapper.dump(ValidationSpec::Ranges.new(list: [range(0, 1), range(5, 4)])) }
      assert_equal "list[1]: low must not be above high", error.message
    end

    it "checks types before the limits, which assume them" do
      error = assert_raises(Typemap::DataError) { mapper.dump(range("a", 1)) }
      assert_equal 'low: expected Integer, got String "a"', error.message
    end
  end
end
