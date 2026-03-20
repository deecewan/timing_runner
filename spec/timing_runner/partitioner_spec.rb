# frozen_string_literal: true

require "spec_helper"

RSpec.describe TimingRunner::Partitioner do
  def build_timing(name, time, file: "spec/#{name}.rb", line: 1, id: "1", stable_key: nil)
    TimingRunner::Timing.new(name:, time:, stable_key:, file:, line:, id:)
  end

  before do
    allow($stdout).to receive(:puts)
  end

  describe ".new" do
    it "rejects runner counts below one" do
      expect { described_class.new([], 0) }.to raise_error(ArgumentError, /at least 1 group/)
    end

    it "balances the slowest examples across partitions" do
      partitioner = described_class.new(
        [
          build_timing("slowest", 10.0),
          build_timing("slow", 9.0),
          build_timing("fast_a", 1.0),
          build_timing("fast_b", 1.0)
        ],
        2
      )

      expect(partitioner.partition_for_group(1).map(&:name)).to eq(%w[slowest fast_b])
      expect(partitioner.partition_for_group(2).map(&:name)).to eq(%w[slow fast_a])
    end

    it "returns empty partitions when there are more runners than tests" do
      partitioner = described_class.new([build_timing("only", 5.0)], 3)

      expect(partitioner.partition_for_group(1).map(&:name)).to eq(["only"])
      expect(partitioner.partition_for_group(2)).to eq([])
      expect(partitioner.partition_for_group(3)).to eq([])
    end

    it "uses stable name ordering instead of file locations when times tie" do
      partitioner = described_class.new(
        [
          build_timing("beta", 1.0, file: "spec/a_spec.rb", line: 1),
          build_timing("alpha", 1.0, file: "spec/z_spec.rb", line: 100),
          build_timing("delta", 1.0, file: "spec/b_spec.rb", line: 10),
          build_timing("gamma", 1.0, file: "spec/c_spec.rb", line: 20)
        ],
        2
      )

      expect(partitioner.partition_for_group(1).map(&:name)).to eq(%w[alpha delta])
      expect(partitioner.partition_for_group(2).map(&:name)).to eq(%w[beta gamma])
    end

    it "sorts tied examples by stable key before the volatile raw name" do
      partitioner = described_class.new(
        [
          build_timing(
            "beta #<Object:0x0000bbbb>",
            1.0,
            stable_key: "beta #<Object:0xOBJECT_ID>",
            file: "spec/c_spec.rb",
            line: 20
          ),
          build_timing(
            "alpha #<Object:0x0000aaaa>",
            1.0,
            stable_key: "alpha #<Object:0xOBJECT_ID>",
            file: "spec/z_spec.rb",
            line: 100
          )
        ],
        2
      )

      expect(partitioner.partition_for_group(1).map(&:stable_key)).to eq(["alpha #<Object:0xOBJECT_ID>"])
      expect(partitioner.partition_for_group(2).map(&:stable_key)).to eq(["beta #<Object:0xOBJECT_ID>"])
    end
  end

  describe "#partition_for_group" do
    it "rejects group numbers outside the configured range" do
      partitioner = described_class.new([build_timing("only", 5.0)], 2)

      expect { partitioner.partition_for_group(0) }.to raise_error(ArgumentError, /not in range/)
      expect { partitioner.partition_for_group(3) }.to raise_error(ArgumentError, /not in range/)
    end
  end
end
