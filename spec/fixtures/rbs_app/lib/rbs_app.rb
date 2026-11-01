# frozen_string_literal: true

# An app whose types live in its sig/rbs_app.rbs, as sord writes it from YARD tags.
module RbsApp
  # A byte count: shadows nothing at the top level, so a bare `Size` inside RbsApp means this.
  class Size < Data.define(:bytes)
    def initialize(bytes: 0) = super
  end

  class Ballooning < Data.define(:raise_at_percent, :mode, :pinned_vms, :floor)
    extend Typemap::Constrain

    constrain :raise_at_percent, in: 1..100

    def initialize(raise_at_percent: 65, mode: "short", pinned_vms: [], floor: Size.new) = super
  end

  class State
    extend Typemap::Constrain

    attr_accessor :log_pane_visible, :ballooning, :note

    constrain :note, type: "String?" # not in the signature, so constrain may give it

    def initialize
      @log_pane_visible = true
      @ballooning = Ballooning.new
      @note = nil
    end
  end

  class Twice
    extend Typemap::Constrain

    attr_accessor :a

    constrain :a, type: "Integer"

    def initialize = @a = 1
  end

  class Unsigned
    attr_accessor :a

    def initialize = @a = 1
  end
end
