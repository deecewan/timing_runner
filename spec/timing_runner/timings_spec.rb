# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe TimingRunner::Timings do
  let(:separator) { described_class::SEPERATOR }

  describe ".parse" do
    it "parses serialized timings" do
      timings = described_class.parse(
        [
          "spec/a_spec.rb[1:1]#{separator}1.5",
          "spec/b_spec.rb[1:2]#{separator}2.25"
        ].join("\n")
      )

      expect(timings.timings.map { |timing| [timing.name, timing.time] }).to eq(
        [
          ["spec/a_spec.rb[1:1]", 1.5],
          ["spec/b_spec.rb[1:2]", 2.25]
        ]
      )
    end

    it "parses timings that include a stable key" do
      timings = described_class.parse(
        "dynamic #<Object:0x0000abcd>#{separator}dynamic #<Object:0xOBJECT_ID>#{separator}1.5"
      )

      timing = timings.timings.first
      expect(timing.name).to eq("dynamic #<Object:0x0000abcd>")
      expect(timing.stable_key).to eq("dynamic #<Object:0xOBJECT_ID>")
      expect(timing.time).to eq(1.5)
    end

    it "returns no timings for empty content" do
      expect(described_class.parse("").timings).to eq([])
    end

    it "rejects missing names" do
      expect { described_class.parse("#{separator}1.5") }
        .to raise_error(described_class::CorruptedDataError, /`name` missing/)
    end

    it "rejects missing times" do
      expect { described_class.parse("spec/a_spec.rb[1:1]") }
        .to raise_error(described_class::CorruptedDataError, /`time` missing/)
    end

    it "rejects lines with too many separators" do
      line = ["spec/a_spec.rb[1:1]", "1.5", "extra"].join(separator)

      expect { described_class.parse(line) }
        .to raise_error(described_class::CorruptedDataError, /too many seperators/)
    end

    it "rejects invalid float values" do
      expect { described_class.parse("spec/a_spec.rb[1:1]#{separator}nope") }
        .to raise_error(described_class::CorruptedDataError, /not a valid float/)
    end
  end

  describe ".parse_from_file" do
    it "returns an empty collection when the file does not exist" do
      expect(described_class.parse_from_file("missing.log").timings).to eq([])
    end
  end

  describe "#dump" do
    it "round-trips serialized timings" do
      serialized = described_class.new(
        timings: [
          TimingRunner::Timing.for("first example", 1.0),
          TimingRunner::Timing.for(
            "dynamic #<Object:0x0000abcd>",
            2.5,
            stable_key: "dynamic #<Object:0xOBJECT_ID>"
          )
        ]
      ).dump

      reparsed = described_class.parse(serialized)

      expect(reparsed.timings.map { |timing| [timing.name, timing.stable_key, timing.time] }).to eq(
        [
          ["first example", nil, 1.0],
          ["dynamic #<Object:0x0000abcd>", "dynamic #<Object:0xOBJECT_ID>", 2.5]
        ]
      )
    end
  end

  describe "#dump_to_file" do
    it "writes serialized timings to the provided file" do
      timings = described_class.new(
        timings: [TimingRunner::Timing.for("written example", 0.75)]
      )

      Tempfile.create("timings") do |file|
        timings.dump_to_file(file)
        file.rewind

        expect(file.read).to eq("written example#{separator}0.75")
      end
    end
  end

  describe "#add" do
    it "appends a new timing" do
      timings = described_class.new

      timings.add(TimingRunner::Timing.for("new example", 1.0))

      expect(timings.timings.map(&:name)).to eq(["new example"])
    end
  end
end
