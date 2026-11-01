# frozen_string_literal: true

require_relative "../../fixtures/rbs_app/lib/rbs_app"

RSpec.describe Confect::Mapper::RBSTypes do
  let(:mapper) { Confect::Mapper.new(types: Confect::Mapper::RBSTypes.new) }

  it "reads types from the sig/ beside the class's own source" do
    state = mapper.load(RbsApp::State, { "log_pane_visible" => false,
                                         "ballooning" => { "mode" => "verbose", "pinned_vms" => ["win11"] } })
    refute state.log_pane_visible
    assert_equal "verbose", state.ballooning.mode
    assert_equal ["win11"], state.ballooning.pinned_vms
  end

  it "resolves a relative name from the declaring namespace" do
    type = mapper.plan_for(RbsApp::Ballooning).properties.find { |property| property.name == :floor }.type
    assert_equal Confect::Mapper::Type::ClassRef.new(klass: RbsApp::Size), type
  end

  it "keeps constrain's limits on a type from the signature" do
    error = assert_raises(Confect::DataError) { mapper.load(RbsApp::Ballooning, { "raise_at_percent" => 0 }) }
    assert_equal "raise_at_percent: 0 is not in 1..100", error.message
  end

  it "rejects a value the signature's type rejects" do
    error = assert_raises(Confect::DataError) { mapper.load(RbsApp::Ballooning, { "mode" => "loud" }) }
    assert_equal 'mode: expected "short" | "verbose", got "loud"', error.message
  end

  it "takes constrain type: for a property the signature leaves out" do
    assert_equal "hi", mapper.load(RbsApp::State, { "note" => "hi" }).note
  end

  it "raises on a type declared both in the signature and by constrain" do
    error = assert_raises(Confect::DefinitionError) { mapper.load(RbsApp::Twice, {}) }
    assert_match(%r{RbsApp::Twice#a: type declared twice: in .*sig/rbs_app\.rbs:\d+ and by `constrain type:`},
                 error.message)
  end

  it "raises on a property neither gives a type" do
    error = assert_raises(Confect::DefinitionError) { mapper.load(RbsApp::Unsigned, {}) }
    assert_match(/RbsApp::Unsigned#a: no type: RbsApp::Unsigned#a has no reader in .*rbs_app\.rbs/, error.message)
  end

  it "reads the signature files it is handed instead" do
    sig = File.expand_path("../../fixtures/rbs_app/sig", __dir__)
    explicit = Confect::Mapper.new(types: Confect::Mapper::RBSTypes.new(sig: [sig]))
    refute explicit.load(RbsApp::State, { "log_pane_visible" => false }).log_pane_visible
  end

  it "raises for a class with no sig/ above its source" do
    error = assert_raises(Confect::DefinitionError) { mapper.load(DataClassSpec::Ballooning, {}) }
    assert_match(%r{no sig/ directory above}, error.message)
  end
end

# Both strategies must accept exactly the same types: the same string, through Confect's own
# parser and through the rbs gem's, builds the same type — or fails the same way.
RSpec.describe Confect::Mapper::TypeParser, "against the rbs gem's parser" do
  rbs = Confect::Mapper::RBSTypes.new(sig: [])
  build = ->(tree) { Confect::Mapper::TypeBuilder.build(tree, "RbsApp") }

  [
    "Integer", "Float", "String", "bool", "Integer?", "Array[String]", "::Array[Integer?]",
    "Hash[String, Integer]", '"short" | "verbose"', '("a" | "b")?', '"a" | "b" | nil', "1 | 2",
    "Size", "RbsApp::Size", "Array[Size]?", "true | false"
  ].each do |source|
    it "builds #{source} the same" do
      assert_equal build.call(rbs.parse_type(source)), build.call(Confect::Mapper::TypeParser.parse(source))
    end
  end

  ["Set[String]", "Hash[Integer, String]", "Integer | String", "nil", "untyped"].each do |source|
    it "rejects #{source} in both" do
      assert_raises(Confect::DefinitionError) { build.call(rbs.parse_type(source)) }
      assert_raises(Confect::DefinitionError) { build.call(Confect::Mapper::TypeParser.parse(source)) }
    end
  end
end
