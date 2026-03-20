# frozen_string_literal: true

require "spec_helper"
require "stringio"
require "tempfile"

RSpec.describe TimingRunner::Logger do
  let(:separator) { TimingRunner::Timings::SEPERATOR }

  def build_notification(description, run_time, metadata: {})
    execution_result = double("ExecutionResult", run_time:)
    example = double("Example", full_description: description, execution_result:, metadata:)
    instance_double(RSpec::Core::Notifications::ExampleNotification, example:)
  end

  describe "#example_passed" do
    it "records timings and dumps them to an IO object" do
      output = StringIO.new
      logger = described_class.new(RSpec::Core::OutputWrapper.new(output))

      logger.send(:example_passed, build_notification("passes quickly", 1.25))
      logger.send(:start_dump, nil)

      expect(output.string).to eq("passes quickly#{separator}1.25\n")
    end

    it "writes serialized timings to a file output" do
      Tempfile.create("timings") do |file|
        logger = described_class.new(file)

        logger.send(:example_passed, build_notification("persists to file", 0.75))
        logger.send(:start_dump, nil)
        file.rewind

        expect(file.read).to eq("persists to file#{separator}0.75")
      end
    end

    it "persists a stable key for dynamic descriptions" do
      output = StringIO.new
      logger = described_class.new(RSpec::Core::OutputWrapper.new(output))
      description = "works with #<Object:0x0000abcd>"

      logger.send(:example_passed, build_notification(description, 0.5))
      logger.send(:start_dump, nil)

      timing = TimingRunner::Timings.parse(output.string.chomp).timings.first
      expect(timing.name).to eq(description)
      expect(timing.stable_key).to eq("works with #<Object:0xOBJECT_ID>")
    end

    it "persists timing_runner_key metadata as the stable key" do
      output = StringIO.new
      logger = described_class.new(RSpec::Core::OutputWrapper.new(output))

      logger.send(
        :example_passed,
        build_notification(
          "serializes #<User:0x0000abcd>",
          0.5,
          metadata: { timing_runner_key: "serialize-user" }
        )
      )
      logger.send(:start_dump, nil)

      timing = TimingRunner::Timings.parse(output.string.chomp).timings.first
      expect(timing.stable_key).to eq("metadata:serialize-user")
    end
  end
end
