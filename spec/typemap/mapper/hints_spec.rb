# frozen_string_literal: true

module HintsSpec
  module Shared
    class Server < Data.define(:id, :url)
      extend Typemap::Constrain

      constrain :id, :url, type: "String"

      def initialize(id: "", url: "") = super
    end
  end

  # `sandboxes` is close enough to `sandbox` for a did-you-mean.
  class Panel < Data.define(:theme, :sandboxes)
    extend Typemap::Constrain

    constrain :theme, type: "String"
    constrain :sandboxes, type: "Integer"

    def initialize(theme: "dark", sandboxes: 0) = super
  end

  class Code < Data.define(:sandbox, :panel)
    extend Typemap::Constrain

    constrain :sandbox, type: "bool"
    constrain :panel, type: "Panel"

    def initialize(sandbox: false, panel: Panel.new) = super
  end

  class Pane < Data.define(:width)
    extend Typemap::Constrain

    constrain :width, type: "Integer"

    def initialize(width: 80) = super
  end

  class Window
    extend Typemap::Constrain

    attr_accessor :title

    constrain :title, type: "String"

    def initialize = @title = "main"
  end

  class Config < Data.define(:server, :code, :pane, :sandbox, :window)
    extend Typemap::Constrain

    constrain :server, type: "Array[Shared::Server]"
    constrain :code, type: "Code"
    constrain :pane, type: "Pane"
    constrain :sandbox, type: "bool"
    constrain :window, type: "Window"

    WINDOW = Window.new

    def initialize(server: [], code: Code.new, pane: Pane.new, sandbox: false, window: WINDOW) = super
  end
end

RSpec.describe Typemap::Mapper, "hinting at the fix" do
  let(:mapper) { Typemap::Mapper.new }

  def error_for(type, value, default: nil)
    klass = Holder.of(type, default)
    assert_raises(Typemap::DataError) { mapper.load(klass, { "value" => value }) }.message
  end

  # The message past `value: expected T, `.
  def found(type, value, default = nil)
    error_for(type, value, default: default).delete_prefix("value: expected #{type}, ")
  end

  def config_error(hash)
    assert_raises(Typemap::DataError) { mapper.load(HintsSpec::Config, hash) }.message
  end

  describe "a single entry where an array belongs" do
    it "tells to wrap an entry that loads, naming its class without the namespace" do
      assert_equal "server: expected Array[Server], got a single Server; wrap it in an array",
                   config_error({ "server" => { "id" => "a" } })
    end
    it "tells to wrap a scalar" do
      assert_equal "value: expected Array[String], got a single String; wrap it in an array",
                   error_for("Array[String]", "a", default: [])
    end
    it "shows the value when it would not load as an entry either" do
      hash = { "port" => 1 }
      assert_equal "server: expected Array[Server], got #{hash.inspect}", config_error({ "server" => hash })
    end
    it "gives no hint for nil, even where an entry may be nil" do
      assert_equal "value: expected Array[String?], got nil", error_for("Array[String?]", nil, default: [])
    end
  end

  describe "an array of one where one entry belongs" do
    it "tells to unwrap an entry that loads" do
      assert_equal "pane: expected Pane, got an array of one Pane; unwrap it",
                   config_error({ "pane" => [{ "width" => 1 }] })
    end
    it "tells so at the root" do
      error = assert_raises(Typemap::DataError) { mapper.load(HintsSpec::Pane, [{}]) }
      assert_equal "expected Pane, got an array of one Pane; unwrap it", error.message
    end
    it "shows the value when the entry would not load" do
      array = [{ "width" => "x" }]
      assert_equal "pane: expected Pane, got #{array.inspect}", config_error({ "pane" => array })
    end
    it "shows the value for two entries" do
      assert_equal "pane: expected Pane, got [{}, {}]", config_error({ "pane" => [{}, {}] })
    end
    it "leaves the default alone when trying the entry" do
      config_error({ "window" => [{ "title" => "other" }] })
      assert_equal "main", HintsSpec::Config::WINDOW.title
    end
  end

  describe "a key an enclosing object has" do
    it "names the top level" do
      assert_equal "pane.sandbox: unknown key; sandbox belongs to the top level",
                   config_error({ "pane" => { "sandbox" => true } })
    end
    it "names the nearest one, over a did-you-mean" do
      assert_equal "code.panel.sandbox: unknown key; sandbox belongs to code",
                   config_error({ "code" => { "panel" => { "sandbox" => true } } })
    end
    it "names an array entry's enclosing object" do
      assert_equal "server[0].sandbox: unknown key; sandbox belongs to the top level",
                   config_error({ "server" => [{ "sandbox" => true }] })
    end
    it "leaves the did-you-mean when no enclosing object has the key" do
      error = assert_raises(Typemap::DataError) { mapper.load(HintsSpec::Panel, { "sandbox" => 1 }) }
      assert_equal "sandbox: unknown key, did you mean sandboxes?", error.message
    end
  end

  describe "quote it" do
    quote = "quote it to make it a string"

    it("for a bool") { assert_equal "got false; #{quote}", found("String", false, "") }
    it("for a Float") { assert_equal "got 1.1; #{quote}", found("String", 1.1, "") }
    it "for a date-time" do
      time = Time.utc(2024, 1, 1)
      assert_equal "got #{time.inspect}; #{quote}", found("String", time, "")
    end
    it "where nil may be too" do
      assert_equal "value: expected String, got false; #{quote}", error_for("String?", false)
    end
    it("for String literals") { assert_equal "got false; #{quote}", found('"yes" | "no"', false, "yes") }
    it("not for literals of other classes") { assert_equal "got false", found('1 | "a"', false, 1) }
    it("not for a container") { assert_equal "got [1]", found("String", [1], "") }
  end

  describe "remove the quotes" do
    it("for a Float") { assert_equal 'got "-1.5"; remove the quotes', found("Float", "-1.5", 0.0) }
    it("for an exponent") { assert_equal 'got "1e3"; remove the quotes', found("Float", "1e3", 0.0) }
    it("for a bool") { assert_equal 'got "true"; remove the quotes', found("bool", "true", false) }
    it("not for hex") { assert_equal 'got "0x1A"', found("Integer", "0x1A", 0) }
    it("not for 70.0 as an Integer") { assert_equal 'got "70.0"', found("Integer", "70.0", 0) }
    it("not for yes") { assert_equal 'got "yes"', found("bool", "yes", false) }
  end

  describe "#dump" do
    it "names a class in full, with no hint" do
      error = assert_raises(Typemap::DataError) { mapper.dump(HintsSpec::Config.new(pane: [HintsSpec::Pane.new])) }
      assert_equal "pane: expected HintsSpec::Pane, got [#<data HintsSpec::Pane width=80>]", error.message
    end
    it "gives no quote hint" do
      error = assert_raises(Typemap::DataError) { mapper.dump(HintsSpec::Pane.new(width: "80")) }
      assert_equal 'width: expected Integer, got "80"', error.message
    end
  end
end
