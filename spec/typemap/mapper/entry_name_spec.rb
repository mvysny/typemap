# frozen_string_literal: true

module EntryNameSpec
  # A data class: a missing url fails the conversion, before any instance exists.
  Server = Data.define(:id, :url) do
    extend Typemap::Constrain

    constrain :id, :url, type: "String"

    def self.entry_name(raw) = raw["id"]
  end

  # An accessor class: a missing url fails the validation, on a finished instance.
  class Llm
    extend Typemap::Constrain

    attr_accessor :name, :model, :port

    constrain :name, type: "String"
    constrain :model, type: "String?", required: true
    constrain :port, type: "Integer", in: 1..65_535

    def initialize
      @name = "default"
      @model = nil
      @port = 80
    end

    def self.entry_name(raw) = "#{raw["name"]}/#{raw["port"]}"
  end

  class Unnamed < Data.define(:id)
    extend Typemap::Constrain

    constrain :id, type: "String"

    def initialize(id: "") = super

    def self.entry_name(raw) = raw["id"]
  end

  class Broken < Data.define(:id)
    extend Typemap::Constrain

    constrain :id, type: "Integer"

    def initialize(id: 0) = super

    def self.entry_name(raw) = raw.fetch("missing")
  end

  class Plain < Data.define(:id)
    extend Typemap::Constrain

    constrain :id, type: "Integer"

    def initialize(id: 0) = super
  end

  class Config < Data.define(:servers, :llms, :spare, :unnamed, :broken, :plain, :by_key)
    extend Typemap::Constrain

    constrain :servers, type: "Array[Server]"
    constrain :llms, type: "Array[Llm]"
    constrain :spare, type: "Array[Server?]"
    constrain :unnamed, type: "Array[Unnamed]"
    constrain :broken, type: "Array[Broken]"
    constrain :plain, type: "Array[Plain]"
    constrain :by_key, type: "Hash[String, Server]"

    def initialize(servers: [], llms: [], spare: [], unnamed: [], broken: [], plain: [], by_key: {}) = super
  end

  class Cluster < Data.define(:nodes)
    extend Typemap::Constrain

    constrain :nodes, type: "Array[Node]"

    def initialize(nodes: []) = super
  end

  class Node < Data.define(:host, :servers)
    extend Typemap::Constrain

    constrain :host, type: "String"
    constrain :servers, type: "Array[Server]"

    def initialize(host: "", servers: []) = super

    def self.entry_name(raw) = raw["host"]
  end
end

RSpec.describe Typemap::Mapper, "naming an array entry" do
  let(:mapper) { Typemap::Mapper.new }

  def load_error(klass, hash) = assert_raises(Typemap::DataError) { mapper.load(klass, hash) }

  def server(id, url = "http://#{id}") = EntryNameSpec::Server.new(id: id, url: url)

  describe "#load" do
    it "names an entry that fails the conversion, from the file's Hash" do
      servers = [{ "id" => "local", "url" => "u" }, { "id" => "grok" }]
      error = load_error(EntryNameSpec::Config, { "servers" => servers })
      assert_equal 'servers[1] "grok".url: required', error.message
      assert_equal 'servers[1] "grok".url', error.path
      assert_equal "required", error.detail
    end

    it "gives entry_name String keys, whatever the file used" do
      error = load_error(EntryNameSpec::Config, { servers: [{ id: "grok", url: 1 }] })
      assert_equal 'servers[0] "grok".url: expected String, got Integer 1', error.message
    end

    it "names an entry that fails the validation, from the finished object with its defaults" do
      error = load_error(EntryNameSpec::Config, { "llms" => [{ "port" => 8080 }] })
      assert_equal 'llms[0] "default/8080".model: required', error.message
    end

    it "names an entry within a named entry" do
      error = load_error(EntryNameSpec::Cluster, { "nodes" => [{ "host" => "a", "servers" => [{ "id" => "grok" }] }] })
      assert_equal 'nodes[0] "a".servers[0] "grok".url: required', error.message
    end

    it "quotes a name, escapes and all, and prints it whole" do
      name = "grok (https://api.x.ai/v1)\nsecond line"
      error = load_error(EntryNameSpec::Config, { "servers" => [{ "id" => name }] })
      assert_equal "servers[0] #{name.inspect}.url: required", error.message
    end

    it "names an entry by the to_s of whatever entry_name gives" do
      assert_equal 'servers[0] "7".id: expected String, got Integer 7',
                   load_error(EntryNameSpec::Config, { "servers" => [{ "id" => 7, "url" => "u" }] }).message
    end

    it "strips the name" do
      assert_equal 'servers[0] "grok".url: required',
                   load_error(EntryNameSpec::Config, { "servers" => [{ "id" => " grok\t" }] }).message
    end

    it "leaves the bare index for a blank name" do
      assert_equal "servers[0].url: required",
                   load_error(EntryNameSpec::Config, { "servers" => [{ "id" => " \n" }] }).message
    end

    it "leaves the bare index when the entry is no Hash, or entry_name gives nothing" do
      assert_equal "servers[0]: expected Server, got Integer 1",
                   load_error(EntryNameSpec::Config, { "servers" => [1] }).message
      assert_equal "unnamed[0].x: unknown key; Unnamed has id",
                   load_error(EntryNameSpec::Config, { "unnamed" => [{ "x" => 1 }] }).message
      assert_equal "plain[0].id: expected Integer, got String \"x\"",
                   load_error(EntryNameSpec::Config, { "plain" => [{ "id" => "x" }] }).message
    end

    it "names an entry of a T? array" do
      error = load_error(EntryNameSpec::Config, { "spare" => [nil, { "id" => "grok" }] })
      assert_equal 'spare[1] "grok".url: required', error.message
    end

    it "warns and leaves the bare index when entry_name raises" do
      error = nil
      assert_output(nil, /broken\[0\] left unnamed, EntryNameSpec::Broken\.entry_name: KeyError/) do
        error = load_error(EntryNameSpec::Config, { "broken" => [{ "id" => "x" }] })
      end
      assert_equal 'broken[0].id: expected Integer, got String "x"', error.message
    end

    it "keeps a Hash entry's path as its key" do
      error = load_error(EntryNameSpec::Config, { "by_key" => { "g" => { "id" => "grok" } } })
      assert_equal "by_key.g.url: required", error.message
    end
  end

  describe "#dump" do
    it "names an entry that fails the validation" do
      llm = EntryNameSpec::Llm.new.tap { |entry| entry.name = "x" }
      error = assert_raises(Typemap::DataError) { mapper.dump(EntryNameSpec::Config.new(llms: [llm])) }
      assert_equal 'llms[0] "x/80".model: required', error.message
    end

    it "names an entry from its other properties when one won't dump" do
      config = EntryNameSpec::Config.new(servers: [server("local"), server("grok", 5)])
      error = assert_raises(Typemap::DataError) { mapper.dump(config) }
      assert_equal 'servers[1] "grok".url: expected String, got Integer 5', error.message
    end

    it "leaves the bare index when the name itself won't dump" do
      config = EntryNameSpec::Config.new(servers: [server(5)])
      error = assert_raises(Typemap::DataError) { mapper.dump(config) }
      assert_equal "servers[0].id: expected String, got Integer 5", error.message
    end
  end
end
