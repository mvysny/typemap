# frozen_string_literal: true

module HintsSpec
  module Shared
    class Server < Data.define(:id, :url)
      extend Typemap::Constrain

      constrain :id, :url, type: "String"

      def initialize(id: "", url: "") = super

      def self.entry_name(raw) = raw["id"]
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

  class Llm < Data.define(:servers)
    extend Typemap::Constrain

    constrain :servers, type: "Array[Shared::Server]"

    def initialize(servers: []) = super
  end

  # `hits` is a required keyword: an entry without it cannot load.
  class Search < Data.define(:key, :hits)
    extend Typemap::Constrain

    constrain :key, type: "String"
    constrain :hits, type: "Integer"

    def initialize(hits:, key: "") = super
  end

  class Config < Data.define(:server, :code, :pane, :sandbox, :window, :llm, :pools, :search, :searches, :mirrors)
    extend Typemap::Constrain

    constrain :server, type: "Array[Shared::Server]"
    constrain :code, type: "Code"
    constrain :pane, type: "Pane"
    constrain :sandbox, type: "bool"
    constrain :window, type: "Window"
    constrain :llm, type: "Array[Llm]"
    constrain :pools, type: "Hash[String, Array[Shared::Server]]"
    constrain :search, type: "Search?"
    constrain :searches, type: "Array[Search]"
    constrain :mirrors, type: "Array[Shared::Server?]"

    WINDOW = Window.new

    def initialize(server: [], code: Code.new, pane: Pane.new, sandbox: false, window: WINDOW, llm: [], pools: {},
                   search: nil, searches: [], mirrors: [])
      super
    end
  end
end

RSpec.describe Typemap::Mapper, "hinting at the fix" do
  let(:mapper) { Typemap::Mapper.new }

  def error_for(type, value, default: nil, source: :ruby)
    klass = Holder.of(type, default)
    assert_raises(Typemap::DataError) { mapper.load(klass, { "value" => value }, source: source) }.message
  end

  # The message past `value: expected T, `.
  def found(type, value, default = nil, source: :json)
    error_for(type, value, default: default, source: source).delete_prefix("value: expected #{type}, ")
  end

  def config_error(hash, source: :ruby)
    assert_raises(Typemap::DataError) { mapper.load(HintsSpec::Config, hash, source: source) }.message
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
    it "shows the value when it shares no key with an entry" do
      hash = { "port" => 1 }
      assert_equal "server: expected Array[Server], got Hash #{hash.inspect}", config_error({ "server" => hash })
    end
    it "shows the value when it shares no key, even where it would load" do
      hash = { "port" => 1 }
      error = assert_raises(Typemap::DataError) { mapper.load(HintsSpec::Config, { "server" => hash }, unknown: :ignore) }
      assert_equal "server: expected Array[Server], got Hash #{hash.inspect}", error.message
    end
    it "gives no hint for nil, even where an entry may be nil" do
      assert_equal "value: expected Array[String?], got nil", error_for("Array[String?]", nil, default: [])
    end
    it "names a scalar entry without its ? where the entries may be nil" do
      assert_equal "value: expected Array[String?], got a single String; wrap it in an array",
                   error_for("Array[String?]", "a", default: [])
    end
    it "tells to wrap a scalar only when it loads as one" do
      assert_equal "value: expected Array[String], got Integer 7", error_for("Array[String]", 7, default: [])
    end

    single = "searches: expected Array[Search], got a single Search; wrap it in an array"
    it "tells to wrap an entry missing a required key" do
      assert_equal single, config_error({ "searches" => { "key" => "a" } })
    end
    it "tells to wrap an entry with a wrong type" do
      assert_equal single, config_error({ "searches" => { "hits" => "1" } })
    end
    it "tells to wrap an entry with an unknown key" do
      assert_equal single, config_error({ "searches" => { "hits" => 1, "bogus" => 2 } })
    end
    it("tells to wrap an empty entry") { assert_equal single, config_error({ "searches" => {} }) }
    it "tells to wrap an entry where the entries may be nil" do
      assert_equal "mirrors: expected Array[Server?], got a single Server; wrap it in an array",
                   config_error({ "mirrors" => { "id" => "a" } })
    end
    it "takes Symbol keys" do
      assert_equal single, config_error({ "searches" => { key: "a" } })
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
    it "shows the value when the entry shares no key" do
      array = [{ "wdth" => 1 }]
      assert_equal "pane: expected Pane, got Array #{array.inspect}", config_error({ "pane" => array })
    end

    one = "search: expected Search, got an array of one Search; unwrap it"
    it "tells to unwrap an entry missing a required key" do
      assert_equal one, config_error({ "search" => [{ "key" => "a" }] })
    end
    it "tells to unwrap an entry with a wrong type" do
      assert_equal one, config_error({ "search" => [{ "hits" => "1" }] })
    end
    it "tells to unwrap an entry with an unknown key" do
      assert_equal one, config_error({ "search" => [{ "hits" => 1, "bogus" => 2 }] })
    end
    it "shows the value for two entries" do
      assert_equal "pane: expected Pane, got Array [{}, {}]", config_error({ "pane" => [{}, {}] })
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
      assert_equal "value: expected String, got false; #{quote}", error_for("String?", false, source: :json)
    end
    it("for String literals") { assert_equal "got false; #{quote}", found('"yes" | "no"', false, "yes") }
    it("not for literals of other classes") { assert_equal "got false", found('1 | "a"', false, 1) }
    it("not for a container") { assert_equal "got [1]", found("String", [1], "") }
    it "after an entry's name" do
      assert_equal "server[0] \"a\".url: expected String, got 7; #{quote}",
                   config_error({ "server" => [{ "id" => "a", "url" => 7 }] }, source: :json)
    end
  end

  describe "remove the quotes" do
    it("for a Float") { assert_equal 'got "-1.5"; remove the quotes', found("Float", "-1.5", 0.0) }
    it("for an exponent") { assert_equal 'got "1e3"; remove the quotes', found("Float", "1e3", 0.0) }
    it("for a bool") { assert_equal 'got "true"; remove the quotes', found("bool", "true", false) }
    it("not for hex") { assert_equal 'got "0x1A"', found("Integer", "0x1A", 0) }
    it("not for 70.0 as an Integer") { assert_equal 'got "70.0"', found("Integer", "70.0", 0) }
    it("not for yes") { assert_equal 'got "yes"', found("bool", "yes", false) }
  end

  describe "source: :ruby, the default" do
    it("names the found value's class") { assert_equal 'got String "70"', found("Integer", "70", 0, source: :ruby) }
    it("leaves nil and a bool bare") { assert_equal "got false", found("String", false, "", source: :ruby) }
    it "leaves an inspect that names its class bare" do
      assert_equal "pane: expected Pane, got #<data HintsSpec::Pane width=80>",
                   config_error({ "pane" => HintsSpec::Pane.new })
    end
    it("never tells to quote") { assert_equal "got Float 1.1", found("String", 1.1, "", source: :ruby) }
  end

  describe "source: :toml" do
    def toml(hash) = config_error(hash, source: :toml)

    it "spells an array of objects as a header, or inline" do
      assert_equal "server: expected Array[Server], got a single Server; " \
                   "write [[server]], not [server], or server = [{…}]", toml({ "server" => { "id" => "a" } })
    end
    it "drops an array entry's index from a header" do
      assert_equal "llm[0].servers: expected Array[Server], got a single Server; " \
                   "write [[llm.servers]], not [llm.servers], or servers = [{…}]",
                   toml({ "llm" => [{ "servers" => { "id" => "a" } }] })
    end
    it "quotes a key that isn't bare" do
      assert_equal "pools.my pool: expected Array[Server], got a single Server; " \
                   'write [[pools."my pool"]], not [pools."my pool"], or "my pool" = [{…}]',
                   toml({ "pools" => { "my pool" => { "id" => "a" } } })
    end
    it "wraps a scalar in brackets" do
      assert_equal "got a single String; wrap it in [ ]", found("Array[String]", "a", [], source: :toml)
    end
    it "unwraps to a header, or inline" do
      assert_equal "pane: expected Pane, got an array of one Pane; write [pane], not [[pane]], or pane = {…}",
                   toml({ "pane" => [{ "width" => 1 }] })
    end
    it "moves a key under its owner's header" do
      assert_equal "code.panel.sandbox: unknown key; sandbox belongs to code, under [code] before [code.panel]",
                   toml({ "code" => { "panel" => { "sandbox" => true } } })
    end
    it "moves a key under an array entry's header" do
      assert_equal "llm[0].servers[0].servers: unknown key; servers belongs to llm[0], " \
                   "under [[llm]] before [[llm.servers]]",
                   toml({ "llm" => [{ "servers" => [{ "servers" => [] }] }] })
    end
    it "moves a key above every header" do
      assert_equal "pane.sandbox: unknown key; sandbox belongs to the top level, before any [header]",
                   toml({ "pane" => { "sandbox" => true } })
    end
  end

  describe "source: :json" do
    it "wraps in brackets" do
      assert_equal "server: expected Array[Server], got a single Server; wrap it in [ ]",
                   config_error({ "server" => { "id" => "a" } }, source: :json)
    end
    it "unwraps" do
      assert_equal "pane: expected Pane, got an array of one Pane; remove the [ ]",
                   config_error({ "pane" => [{ "width" => 1 }] }, source: :json)
    end
    it "moves a key out of its braces" do
      assert_equal "code.panel.sandbox: unknown key; sandbox belongs to code; move it out of code.panel's { }",
                   config_error({ "code" => { "panel" => { "sandbox" => true } } }, source: :json)
    end
  end

  describe "source: :yaml" do
    it "wraps with a dash" do
      assert_equal "server: expected Array[Server], got a single Server; put \"- \" before it",
                   config_error({ "server" => { "id" => "a" } }, source: :yaml)
    end
    it "unwraps" do
      assert_equal "pane: expected Pane, got an array of one Pane; remove the \"- \"",
                   config_error({ "pane" => [{ "width" => 1 }] }, source: :yaml)
    end
    it "names YAML's booleans" do
      assert_equal "got false; quote it to make it a string; YAML reads yes, no, on and off as booleans",
                   found("String", false, "", source: :yaml)
    end
    it("quotes a number plainly") {
      assert_equal "got 1.1; quote it to make it a string", found("String", 1.1, "", source: :yaml)
    }
    it "dedents a key" do
      assert_equal "pane.sandbox: unknown key; sandbox belongs to the top level; dedent it",
                   config_error({ "pane" => { "sandbox" => true } }, source: :yaml)
    end
  end

  it "rejects an unknown source" do
    error = assert_raises(ArgumentError) { mapper.load(HintsSpec::Pane, {}, source: :xml) }
    assert_equal "source: must be :ruby, :toml, :json or :yaml, got :xml", error.message
  end

  describe "#dump" do
    it "names a class in full, worded for Ruby, with no hint" do
      error = assert_raises(Typemap::DataError) { mapper.dump(HintsSpec::Config.new(pane: [HintsSpec::Pane.new])) }
      assert_equal "pane: expected HintsSpec::Pane, got Array [#<data HintsSpec::Pane width=80>]", error.message
    end
    it "gives no quote hint" do
      error = assert_raises(Typemap::DataError) { mapper.dump(HintsSpec::Pane.new(width: "80")) }
      assert_equal 'width: expected Integer, got String "80"', error.message
    end
  end
end
