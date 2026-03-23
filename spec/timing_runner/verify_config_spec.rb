# typed: true

require "spec_helper"

RSpec.describe TimingRunner::VerifyConfig do
  describe ".parse_args" do
    it "parses the input file and rspec args after --" do
      parsed =
        described_class.parse_args(
          ["--input-file", "tmp/timings.log", "--", "--tag", "~release", "spec/models"]
        )

      expect(parsed).to eq(
        input_file: "tmp/timings.log",
        rspec_args: ["--tag", "~release", "spec/models"]
      )
    end
  end
end
