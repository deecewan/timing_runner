# frozen_string_literal: true

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

  # it "has never been run" do
  #   expect(true).to eq(true)
  # end
end
