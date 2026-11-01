# frozen_string_literal: true

module RequiredKeysSpec
  # Every member required: Data's own initialize, untouched.
  class Token < Data.define(:value)
    extend Typemap::Constrain

    constrain :value, type: "String"
  end

  class Llm < Data.define(:api_key, :model)
    extend Typemap::Constrain

    constrain :api_key, :model, type: "String"

    def initialize(api_key:, model: "gpt-5") = super
  end

  class Agent < Data.define(:llm, :fallbacks, :name)
    extend Typemap::Constrain

    constrain :llm, type: "Llm"
    constrain :fallbacks, type: "Array[Llm]"
    constrain :name, type: "String"

    def initialize(llm:, fallbacks: [], name: "agent") = super
  end

  # The parent's default gives the nested required key, so the file need not.
  class Preset < Data.define(:llm)
    extend Typemap::Constrain

    constrain :llm, type: "Llm"

    def initialize(llm: Llm.new(api_key: "built-in")) = super
  end

  class Window < Data.define(:width, :height)
    extend Typemap::Constrain

    constrain :width, :height, type: "Integer", in: (1..)

    def initialize(width: 80, height: 24) = super
  end

  # A required keyword beside a nested default the file may set in part.
  class Screen < Data.define(:id, :window)
    extend Typemap::Constrain

    constrain :id, type: "String"
    constrain :window, type: "Window"

    def initialize(id:, window: Window.new(width: 100)) = super
  end

  class Note < Data.define(:text)
    extend Typemap::Constrain

    constrain :text, type: "String?"
  end

  class Secret
    extend Typemap::Constrain

    attr_accessor :api_key, :model

    constrain :api_key, type: "String?", required: true
    constrain :model, type: "String"

    def initialize
      @api_key = nil
      @model = "gpt-5"
    end
  end

  class Settings
    extend Typemap::Constrain

    attr_accessor :secret

    constrain :secret, type: "Secret"

    def initialize = @secret = Secret.new
  end
end

RSpec.describe Typemap::Mapper, "with required keys" do
  let(:mapper) { Typemap::Mapper.new }

  def data_error(klass, hash) = assert_raises(Typemap::DataError) { mapper.load(klass, hash) }.message

  describe "a data class's keyword without a default" do
    it "must be in the file" do
      assert_equal "api_key: required", data_error(RequiredKeysSpec::Llm, {})
      assert_equal RequiredKeysSpec::Llm.new(api_key: "k"), mapper.load(RequiredKeysSpec::Llm, { "api_key" => "k" })
    end

    it "is every member when Data's own initialize is left as is" do
      assert_equal "value: required", data_error(RequiredKeysSpec::Token, {})
      assert_equal "t", mapper.load(RequiredKeysSpec::Token, { "value" => "t" }).value
    end

    it "raises with its full path, nested and in an Array" do
      assert_equal "llm: required", data_error(RequiredKeysSpec::Agent, {})
      assert_equal "llm.api_key: required", data_error(RequiredKeysSpec::Agent, { "llm" => {} })
      assert_equal "fallbacks[0].api_key: required",
                   data_error(RequiredKeysSpec::Agent, { "llm" => { "api_key" => "k" }, "fallbacks" => [{}] })
    end

    it "is satisfied by the parent's default" do
      preset = mapper.load(RequiredKeysSpec::Preset, { "llm" => { "model" => "small" } })
      assert_equal RequiredKeysSpec::Llm.new(api_key: "built-in", model: "small"), preset.llm
    end

    it "keeps a nested table loading onto the default's nested object" do
      screen = mapper.load(RequiredKeysSpec::Screen, { "id" => "s", "window" => { "height" => 50 } })
      assert_equal RequiredKeysSpec::Window.new(width: 100, height: 50), screen.window
    end

    it "takes null when its type is nilable" do
      assert_nil mapper.load(RequiredKeysSpec::Note, { "text" => nil }).text
      assert_equal "text: required", data_error(RequiredKeysSpec::Note, {})
    end

    it "round-trips through dump" do
      agent = RequiredKeysSpec::Agent.new(llm: RequiredKeysSpec::Llm.new(api_key: "k"))
      assert_equal agent, mapper.load(RequiredKeysSpec::Agent, mapper.dump(agent))
    end
  end

  describe "an accessor class's required:" do
    it "raises when the result still holds nil" do
      assert_equal "api_key: required", data_error(RequiredKeysSpec::Secret, {})
      assert_equal "api_key: required", data_error(RequiredKeysSpec::Secret, { "api_key" => nil })
      assert_equal "k", mapper.load(RequiredKeysSpec::Secret, { "api_key" => "k" }).api_key
    end

    it "raises inside a nested table the file leaves out" do
      assert_equal "secret.api_key: required", data_error(RequiredKeysSpec::Settings, {})
    end

    it "raises on dump" do
      error = assert_raises(Typemap::DataError) { mapper.dump(RequiredKeysSpec::Settings.new) }
      assert_equal "secret.api_key: required", error.message
    end
  end

  describe "a class that declares it wrong" do
    def definition_error(klass) = assert_raises(Typemap::DefinitionError) { mapper.load(klass, {}) }.message

    def data_class(*members, type: "Integer", &)
      Data.define(*members) do
        extend Typemap::Constrain

        constrain(*members, type: type)
        class_eval(&) if block_given?
      end
    end

    it "raises on required: in a data class" do
      klass = data_class(:port) do
        constrain :port, required: true
        def initialize(port: 1) = super
      end
      assert_match(/#port: required: is for an accessor class; in a data class, a keyword without a default/,
                   definition_error(klass))
    end

    it "raises on an initialize that does not say which keys are required" do
      klass = data_class(:port) { def initialize(**opts) = super(port: 1, **opts) }
      assert_match(/#initialize takes \[\[:keyrest, :opts\]\]; Typemap reads which keys are required only/,
                   definition_error(klass))
    end

    it "raises on an initialize with no keyword for a member" do
      klass = data_class(:port, :host) { def initialize(port: 1) = super(port: port, host: "h") }
      assert_match(/#initialize takes no keyword host/, definition_error(klass))
    end

    it "raises on a required keyword the file cannot give" do
      klass = Data.define(:port, :host) do
        extend Typemap::Constrain

        constrain :port, type: "Integer"
        ignore :host
        def initialize(host:, port: 1) = super
      end
      assert_match(/#initialize requires host, not a mapped property/, definition_error(klass))
    end

    it "checks the other defaults on load, there being no bare new" do
      klass = data_class(:port, :timeout) { def initialize(port:, timeout: "x") = super }
      error = assert_raises(Typemap::DefinitionError) { mapper.load(klass, { "port" => 1 }) }
      assert_match(/#timeout: its default "x" does not fit Integer/, error.message)
    end

    it "raises on required: on a type that is never nil" do
      assert_match(/value: required: on String, which can never be missing/,
                   definition_error(Holder.of("String", "x", required: true)))
    end

    it "raises on required: with a default other than nil" do
      assert_match(/value: required: its default must be nil/,
                   definition_error(Holder.of("String?", "x", required: true)))
    end
  end
end
