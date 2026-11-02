# frozen_string_literal: true

module UniqueSpec
  Server = Data.define(:id, :url) do
    extend Typemap::Constrain

    constrain :id, :url, type: "String"

    def self.entry_name(raw) = raw["id"]
  end

  class Mirror < Data.define(:name, :url)
    extend Typemap::Constrain

    constrain :name, type: "String?"
    constrain :url, type: "String"

    def initialize(name: nil, url: "") = super
  end

  # An accessor class: identity equality, unless it says otherwise.
  class Llm
    extend Typemap::Constrain

    attr_accessor :name

    constrain :name, type: "String"

    def initialize = @name = "default"
  end

  # An accessor class with value equality of its own.
  class Port
    extend Typemap::Constrain

    attr_accessor :number

    constrain :number, type: "Integer"

    def initialize = @number = 0
    def eql?(other) = other.is_a?(Port) && number == other.number
    def hash = number.hash
  end

  class Config < Data.define(:servers, :mirrors, :tags, :spare, :llms, :ports, :hosts)
    extend Typemap::Constrain

    constrain :servers, type: "Array[Server]", unique_by: :id
    constrain :mirrors, type: "Array[Mirror]?", unique_by: :name
    constrain :tags, type: "Array[String?]", unique: true
    constrain :spare, type: "Array[Server]", unique: true
    constrain :llms, type: "Array[Llm]", unique_by: :name
    constrain :ports, type: "Array[Port]", unique: true
    constrain :hosts, type: "Array[Mirror]", unique_by: ->(mirror) { mirror.url.downcase }

    def initialize(servers: [], mirrors: nil, tags: [], spare: [], llms: [], ports: [], hosts: []) = super
  end

  class Defaulted < Data.define(:servers)
    extend Typemap::Constrain

    constrain :servers, type: "Array[Server]", unique_by: :id

    def initialize(servers: [Server.new(id: "a", url: "x"), Server.new(id: "a", url: "y")]) = super
  end

  class Twice < Data.define(:servers)
    extend Typemap::Constrain

    constrain :servers, type: "Array[Server]", unique: true
    constrain :servers, unique_by: :id

    def initialize(servers: []) = super
  end
end

RSpec.describe Typemap::Mapper, "unique: and unique_by:" do
  let(:mapper) { Typemap::Mapper.new }

  def load_error(hash) = assert_raises(Typemap::DataError) { mapper.load(UniqueSpec::Config, hash) }.message

  def definition_error(klass) = assert_raises(Typemap::DefinitionError) { mapper.load(klass, {}) }.message

  def holder(type, default, **limits) = Holder.of(type, default, **limits)

  def server(id, url = "http://#{id}") = { "id" => id, "url" => url }

  describe "unique_by: a property" do
    it "takes distinct entries" do
      config = mapper.load(UniqueSpec::Config, { "servers" => [server("a"), server("b")] })
      assert_equal %w[a b], config.servers.map(&:id)
    end

    it "points at the second entry's property, named, and at the first by index" do
      servers = [server("local"), server("grok"), server("local", "http://other")]
      assert_equal 'servers[2] "local".id: duplicate of servers[0], both "local"', load_error({ "servers" => servers })
    end

    it "takes an Array[T]? and lets its nil through" do
      assert_nil mapper.load(UniqueSpec::Config, { "mirrors" => nil }).mirrors
      mirrors = [{ "name" => "eu", "url" => "a" }, { "name" => "eu", "url" => "b" }]
      assert_equal 'mirrors[1].name: duplicate of mirrors[0], both "eu"', load_error({ "mirrors" => mirrors })
    end

    it "takes two nils as duplicates, as Ruby's nil == nil" do
      assert_equal "mirrors[1].name: duplicate of mirrors[0], both nil",
                   load_error({ "mirrors" => [{ "url" => "a" }, { "url" => "b" }] })
    end

    it "reads an accessor class's property" do
      assert_equal 'llms[1].name: duplicate of llms[0], both "default"', load_error({ "llms" => [{}, {}] })
    end
  end

  describe "unique_by: a function" do
    it "compares what the function gives, the path stopping at the entry" do
      hosts = [{ "url" => "http://X" }, { "url" => "http://y" }, { "url" => "http://x" }]
      assert_equal 'hosts[2]: duplicate of hosts[0], both "http://x"', load_error({ "hosts" => hosts })
    end
  end

  describe "unique: true" do
    it "compares scalars" do
      assert_equal ["a", nil, "b"], mapper.load(UniqueSpec::Config, { "tags" => ["a", nil, "b"] }).tags
      assert_equal 'tags[2]: duplicate of tags[0], both "a"', load_error({ "tags" => %w[a b a] })
      assert_equal "tags[1]: duplicate of tags[0], both nil", load_error({ "tags" => [nil, nil] })
    end

    it "compares data class entries by value, naming the entry and not printing it" do
      assert_equal 'spare[1] "a": duplicate of spare[0]', load_error({ "spare" => [server("a"), server("a")] })
      assert_equal 2, mapper.load(UniqueSpec::Config, { "spare" => [server("a"), server("a", "u")] }).spare.size
    end

    it "takes an accessor class with value equality of its own" do
      assert_equal "ports[1]: duplicate of ports[0]", load_error({ "ports" => [{ "number" => 1 }, { "number" => 1 }] })
    end
  end

  describe "#dump" do
    it "raises on duplicates, the entry named" do
      config = UniqueSpec::Config.new(servers: [UniqueSpec::Server.new(id: "a", url: "x")] * 2)
      error = assert_raises(Typemap::DataError) { mapper.dump(config) }
      assert_equal 'servers[1] "a".id: duplicate of servers[0], both "a"', error.message
    end
  end

  describe "reading the class" do
    it "raises on a default with duplicates" do
      assert_match(/Defaulted#servers: its default \[1\]\.id: duplicate of \[0\], both "a"/,
                   definition_error(UniqueSpec::Defaulted))
    end

    it "raises on a type that is no Array" do
      assert_match(/unique: limits only an Array, not String\z/, definition_error(holder("String", "", unique: true)))
      assert_match(/unique_by: :id limits only an Array, not Hash\[String, String\]; a Hash's keys are unique/,
                   definition_error(holder("Hash[String, String]", {}, unique_by: :id)))
    end

    it "raises on unique: over entries compared by identity" do
      klass = holder("Array[UniqueSpec::Llm]", [], unique: true)
      assert_match(/unique: on Array\[UniqueSpec::Llm\] compares the entries by identity, .* with unique_by:/,
                   definition_error(klass))
    end

    it "raises on unique_by: a Symbol over entries that are no class" do
      assert_match(/:size reads a property of each entry, so unique_by: takes it on an Array of a class, not Array\[S/,
                   definition_error(holder("Array[String]", [], unique_by: :size)))
      assert_match(/not Array\[UniqueSpec::Server\?\]/,
                   definition_error(holder("Array[UniqueSpec::Server?]", [], unique_by: :id)))
    end

    it "raises on unique_by: naming no property, with a guess or the list" do
      assert_match(/unique_by: :idd names no property of UniqueSpec::Server, did you mean id\?/,
                   definition_error(holder("Array[UniqueSpec::Server]", [], unique_by: :idd)))
      assert_match(/unique_by: :host names no property of UniqueSpec::Server; UniqueSpec::Server has id, url/,
                   definition_error(holder("Array[UniqueSpec::Server]", [], unique_by: :host)))
    end

    it "raises on unique: and unique_by: from two constrain calls" do
      assert_match(/Twice#servers: unique: and unique_by: together/, definition_error(UniqueSpec::Twice))
    end
  end
end
