# frozen_string_literal: true

RSpec.describe Confect do
  it "has a semantic version number" do
    assert_match(/\A\d+\.\d+\.\d+\z/, Confect::VERSION)
  end
end
