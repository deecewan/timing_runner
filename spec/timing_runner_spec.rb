# frozen_string_literal: true

require_relative "./support/some_shared_examples.rb"

RSpec.describe TimingRunner do
  it "has a version number" do
    sleep 0.5
    expect(TimingRunner::VERSION).not_to be nil
  end

  it "passes" do
    sleep 0.5
    expect(true).to eq(true)
  end

  it "does something useful" do
    expect(false).to eq(true)
  end

  it "takes a while" do
    sleep 0.5
    expect(true).to eq(true)
  end

  context "something" do
    it "passes" do
      sleep 0.5
      expect(true).to eq(true)
    end
  end

  context "sub" do
    include_examples "test shared examples"

    it "works" do
      expect(true).to eq(true)
    end
  end

  # it "has never been run" do
  #   expect(true).to eq(true)
  # end
end
