# frozen_string_literal: true

require "spec_helper"

RSpec.describe TimingRunner::Identity do
  describe ".normalize" do
    it "replaces Ruby object ids with a stable token" do
      expect(described_class.normalize("does work for #<Object:0x0000abcd>"))
        .to eq("does work for #<Object:0xOBJECT_ID>")
    end
  end

  describe ".for_name" do
    it "includes shared example names in the stable key" do
      key = described_class.for_name(
        "outer behaves correctly",
        shared_group_names: ["common behavior", "shared setup"]
      )

      expect(key).to eq(
        "outer behaves correctly|shared:common behavior|shared:shared setup"
      )
    end

    it "uses an explicit metadata override when provided" do
      key = described_class.for_name(
        "does work for #<Object:0x0000abcd>",
        explicit_key: "stable-user-key"
      )

      expect(key).to eq("metadata:stable-user-key")
    end
  end

  describe ".for_example" do
    it "uses timing_runner_key metadata when provided" do
      example = instance_double(
        "Example",
        full_description: "serializes #<User:0x0000abcd>",
        metadata: { timing_runner_key: "serialize-user" }
      )

      expect(described_class.for_example(example)).to eq("metadata:serialize-user")
    end
  end
end
