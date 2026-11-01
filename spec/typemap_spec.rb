# frozen_string_literal: true

RSpec.describe Typemap do
  it "has a semantic version number" do
    assert_match(/\A\d+\.\d+\.\d+\z/, Typemap::VERSION)
  end
end
