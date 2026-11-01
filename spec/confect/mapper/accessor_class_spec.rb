# frozen_string_literal: true

module AccessorClassSpec
  Window = Data.define(:width, :height) do
    extend Confect::Constrain

    constrain :width, :height, type: "Integer", in: (1..)

    def initialize(width: 80, height: 24) = super
  end

  class State
    extend Confect::Constrain

    attr_accessor :system_pane_visible, :log_pane_visible
    attr_accessor :window
    attr_accessor :on_change
    attr_reader :path

    constrain :system_pane_visible, :log_pane_visible, type: "bool"
    constrain :window, type: "Window"
    ignore :on_change

    def initialize(path: "/tmp/state.json")
      @path = path
      @system_pane_visible = true
      @log_pane_visible = true
      @window = Window.new
      @secret = 1
    end

    # A reader with no writer.
    def label = "state"

    def self.built = @built ||= 0

    protected

    attr_accessor :revision
  end

  DEFAULT_WINDOW = Window.new(width: 100, height: 40)

  class Shared
    extend Confect::Constrain

    attr_accessor :window

    constrain :window, type: "Window"

    def initialize
      @window = DEFAULT_WINDOW
    end
  end
end

RSpec.describe Confect::Mapper, "with an accessor class" do
  let(:mapper) { Confect::Mapper.new }

  it "maps the public reader + writer pairs, in declaration order, without the ignored one" do
    assert_equal %i[system_pane_visible log_pane_visible window],
                 mapper.plan_for(AccessorClassSpec::State).names
  end

  it "loads by a bare new, then the setters" do
    state = mapper.load(AccessorClassSpec::State, { "log_pane_visible" => false, "window" => { "height" => 50 } })
    refute state.log_pane_visible
    assert state.system_pane_visible
    assert_equal AccessorClassSpec::Window.new(width: 80, height: 50), state.window
    assert_equal "/tmp/state.json", state.path
  end

  it "dumps the mapped properties only" do
    assert_equal({ "system_pane_visible" => true, "log_pane_visible" => true,
                   "window" => { "width" => 80, "height" => 24 } },
                 mapper.dump(AccessorClassSpec::State.new))
  end

  it "rejects a key for a reader with no writer as unknown" do
    error = assert_raises(Confect::DataError) { mapper.load(AccessorClassSpec::State, { "path" => "/etc" }) }
    assert_equal "path", error.path
  end

  it "rejects a key for the ignored accessor as unknown" do
    assert_raises(Confect::DataError) { mapper.load(AccessorClassSpec::State, { "on_change" => 1 }) }
  end

  it "rejects a non-boolean" do
    error = assert_raises(Confect::DataError) { mapper.load(AccessorClassSpec::State, { "log_pane_visible" => "no" }) }
    assert_equal 'log_pane_visible: expected bool, got "no"', error.message
  end

  it "never changes a default shared beyond the load" do
    loaded = mapper.load(AccessorClassSpec::Shared, { "window" => { "width" => 7 } })
    assert_equal 7, loaded.window.width
    assert_equal 40, loaded.window.height
    assert_equal 100, AccessorClassSpec::DEFAULT_WINDOW.width
  end
end

RSpec.describe Confect::Mapper::AccessorShape do
  it "orders accessors declared on one line as they stand in it" do
    klass = Class.new do
      attr_accessor :zeta, :alpha
      attr_accessor :middle
    end
    assert_equal %i[zeta alpha middle], Confect::Mapper::AccessorShape.properties(klass)
  end
end
