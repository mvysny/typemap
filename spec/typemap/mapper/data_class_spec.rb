# frozen_string_literal: true

module DataClassSpec
  class Ballooning < Data.define(:raise_at_percent, :shrink_at_percent, :pinned_vms)
    extend Typemap::Constrain

    constrain :raise_at_percent, :shrink_at_percent, type: "Integer", in: 1..100
    constrain :pinned_vms, type: "Array[String]"

    def initialize(raise_at_percent: 65, shrink_at_percent: 55, pinned_vms: []) = super

    def validate
      raise "raise_at_percent must be above shrink_at_percent" unless raise_at_percent > shrink_at_percent
    end
  end

  class Config < Data.define(:ballooning, :name)
    extend Typemap::Constrain

    constrain :ballooning, type: "Ballooning"
    constrain :name, type: "String?"

    def initialize(ballooning: Ballooning.new(raise_at_percent: 80), name: nil) = super
  end

  # Two keys close enough that a typo matches both; `raise_at` required.
  class Twins < Data.define(:raise_at, :raise_by)
    extend Typemap::Constrain

    constrain :raise_at, :raise_by, type: "Integer"

    def initialize(raise_at:, raise_by: 1) = super
  end
end

RSpec.describe Typemap::Mapper, "with a data class" do
  let(:mapper) { Typemap::Mapper.new }

  describe "#load" do
    it "keeps the default of every key the file leaves out" do
      ballooning = mapper.load(DataClassSpec::Ballooning, { "shrink_at_percent" => 40 })
      assert_equal DataClassSpec::Ballooning.new(raise_at_percent: 65, shrink_at_percent: 40), ballooning
    end

    it "takes Symbol keys as their Strings" do
      assert_equal 70, mapper.load(DataClassSpec::Ballooning, { raise_at_percent: 70 }).raise_at_percent
    end

    it "loads a nested table onto the default's nested object, not onto the nested class's own default" do
      config = mapper.load(DataClassSpec::Config, { "ballooning" => { "shrink_at_percent" => 30 } })
      assert_equal 80, config.ballooning.raise_at_percent
      assert_equal 30, config.ballooning.shrink_at_percent
    end

    it "raises on an unknown key, with its path" do
      error = assert_raises(Typemap::DataError) { mapper.load(DataClassSpec::Config, { "ballooning" => { "rasie" => 1 } }) }
      assert_equal "ballooning.rasie", error.path
      assert_equal "ballooning.rasie: unknown key; Ballooning has raise_at_percent, " \
                   "shrink_at_percent, pinned_vms", error.message
    end

    it "suggests the key a misspelled one meant" do
      error = assert_raises(Typemap::DataError) { mapper.load(DataClassSpec::Ballooning, { "rasie_at_percent" => 1 }) }
      assert_equal "rasie_at_percent: unknown key, did you mean raise_at_percent?", error.message
    end

    it "suggests every close key" do
      error = assert_raises(Typemap::DataError) { mapper.load(DataClassSpec::Twins, { "raise_at" => 1, "raise_bt" => 1 }) }
      assert_equal "raise_bt: unknown key, did you mean raise_by or raise_at?", error.message
    end

    it "reports a misspelled required key as unknown, not as missing" do
      error = assert_raises(Typemap::DataError) { mapper.load(DataClassSpec::Twins, { "raise_bt" => 1, "raise_by" => 2 }) }
      assert_equal "raise_bt: unknown key, did you mean raise_by or raise_at?", error.message
    end

    it "ignores an unknown key when told to" do
      config = mapper.load(DataClassSpec::Config, { "newer" => 1, "ballooning" => { "rasie" => 1 } }, unknown: :ignore)
      assert_equal DataClassSpec::Config.new, config
    end

    it "rejects a value outside its limits" do
      error = assert_raises(Typemap::DataError) { mapper.load(DataClassSpec::Ballooning, { "raise_at_percent" => 170 }) }
      assert_equal "raise_at_percent: must be 1 to 100, got 170", error.message
    end

    it "calls validate, prefixing its message with the object's path" do
      error = assert_raises(Typemap::DataError) do
        mapper.load(DataClassSpec::Config, { "ballooning" => { "raise_at_percent" => 50 } })
      end
      assert_equal "ballooning: raise_at_percent must be above shrink_at_percent", error.message
      assert_kind_of RuntimeError, error.cause
    end

    it "raises when the root is not a Hash" do
      error = assert_raises(Typemap::DataError) { mapper.load(DataClassSpec::Ballooning, [1]) }
      assert_equal "expected Ballooning, got [1]", error.message
    end

    it "raises when a nested value is not a Hash" do
      error = assert_raises(Typemap::DataError) { mapper.load(DataClassSpec::Config, { "ballooning" => 5 }) }
      assert_equal "ballooning: expected Ballooning, got 5", error.message
    end

    it "rejects an unknown unknown: policy" do
      assert_raises(ArgumentError) { mapper.load(DataClassSpec::Ballooning, {}, unknown: :warn) }
    end
  end

  describe "#dump" do
    it "gives String keys in members order, nested objects as Hashes" do
      dumped = mapper.dump(DataClassSpec::Config.new(name: "x"))
      assert_equal({ "ballooning" => { "raise_at_percent" => 80, "shrink_at_percent" => 55, "pinned_vms" => [] },
                     "name" => "x" }, dumped)
      assert_equal %w[ballooning name], dumped.keys
    end

    it "round-trips through load" do
      config = DataClassSpec::Config.new(ballooning: DataClassSpec::Ballooning.new(pinned_vms: ["win11"]), name: "n")
      assert_equal config, mapper.load(DataClassSpec::Config, mapper.dump(config))
    end

    it "raises on a value its type rejects, with its path" do
      broken = DataClassSpec::Ballooning.new(pinned_vms: [:sym])
      error = assert_raises(Typemap::DataError) { mapper.dump(broken) }
      assert_equal "pinned_vms[0]: expected String, got :sym", error.message
    end
  end
end
