# frozen_string_literal: true

module FrozenSpec
  # Defaults built without `# frozen_string_literal`'s help: every String here is `+"…"`.
  class Search < Data.define(:engines, :params)
    extend Typemap::Constrain

    constrain :engines, type: "Array[String]"
    constrain :params, type: "Hash[String, Object]"

    def initialize(engines: [+"brave"], params: { +"stop" => [+"x"] }) = super
  end

  class Tags
    extend Typemap::Constrain

    attr_accessor :tags, :search

    constrain :tags, type: "Array[String]"
    constrain :search, type: "Search"

    def initialize
      @tags = [+"a"]
      @search = Search.new
    end
  end

  class Root < Data.define(:name, :search, :servers, :tags, :log)
    extend Typemap::Constrain

    constrain :name, type: "String"
    constrain :search, type: "Search"
    constrain :servers, type: "Array[Search]"
    constrain :tags, type: "Tags"
    ignore :log

    def initialize(name: +"root", search: Search.new, servers: [Search.new], tags: Tags.new, log: +"") = super
  end

  ENGINES = [+"exa"].freeze

  class Shared < Data.define(:engines)
    extend Typemap::Constrain

    constrain :engines, type: "Array[String]"

    def initialize(engines: ENGINES) = super
  end
end

RSpec.describe Typemap::Mapper, "freezing a loaded data object's values" do
  let(:mapper) { Typemap::Mapper.new }

  it "freezes the Arrays, Hashes and Strings the file gave, nested ones included" do
    search = { "engines" => [+"exa"], "params" => { "a" => [{ "b" => +"c" }] } }
    root = mapper.load(FrozenSpec::Root, { "name" => +"x", "search" => search })
    assert root.name.frozen?
    assert root.search.engines.frozen?
    assert root.search.engines[0].frozen?
    assert root.search.params.frozen?
    assert root.search.params["a"].frozen?
    assert root.search.params["a"][0].frozen?
    assert root.search.params["a"][0]["b"].frozen?
  end

  it "freezes the defaults of the keys the file leaves out, a nested default object's too" do
    root = mapper.load(FrozenSpec::Root, {})
    assert root.name.frozen?
    assert root.search.engines.frozen?
    assert root.search.engines[0].frozen?
    assert root.search.params["stop"][0].frozen?
  end

  it "freezes the values of a data object inside a default Array" do
    root = mapper.load(FrozenSpec::Root, {})
    assert root.servers.frozen?
    assert root.servers[0].engines.frozen?
  end

  it "leaves an accessor object's values mutable, but freezes a data object nested in it" do
    root = mapper.load(FrozenSpec::Root, { "tags" => { "tags" => [+"b"] } })
    refute root.tags.tags.frozen?
    refute root.tags.tags[0].frozen?
    assert root.tags.search.engines.frozen?
  end

  it "never freezes the caller's Arrays and Hashes, but freezes its Strings a data object holds" do
    engines = [+"exa"]
    hash = { "search" => { "engines" => engines } }
    root = mapper.load(FrozenSpec::Root, hash)
    refute hash.frozen?
    refute engines.frozen?
    assert engines[0].frozen?
    assert_same engines[0], root.search.engines[0]
  end

  it "leaves an ignored property alone" do
    refute mapper.load(FrozenSpec::Root, {}).log.frozen?
  end

  it "freezes the Strings inside a frozen default Array" do
    assert mapper.load(FrozenSpec::Shared, {}).engines[0].frozen?
  end

  it "leaves an object given to dump as it was" do
    search = FrozenSpec::Search.new
    mapper.dump(search)
    refute search.engines.frozen?
  end
end
