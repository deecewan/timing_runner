# typed: true

module TimingRunner
  class Partitioner
    extend T::Sig

    TimingArray = T.type_alias { T::Array[Timing] }
    NestedTimings = T.type_alias { T::Array[TimingArray] }

    class Partition < T::Struct
      const :timings, TimingArray, default: []
      prop :total_time, Float, default: 0.0
    end

    sig { params(timings: TimingArray, num_groups: Integer).void }

    def initialize(timings, num_groups)
      if num_groups < 1
        raise ArgumentError, "must have at least 1 group"
      end

      @num_groups = T.let(num_groups, Integer)
      @groups = T.let(create_groups(timings), NestedTimings)
    end

    sig { params(group: Integer).returns(TimingArray) }

    def partition_for_group(group)
      if group < 1 || group > @num_groups
        raise ArgumentError, "group #{group} not in range (1, #{@num_groups})"
      end

      T.must(@groups[group - 1])
    end

    private

    # TODO: if the time is 0, add the average overall time
    sig { params(timings: TimingArray).returns(NestedTimings) }

    def create_groups(timings)
      # sort first so we get a stable order
      sorted = timings.sort_by { |t| [-1 * t.time, t.location] }

      # create the partitions we're going to temporarily store the data in
      partitions = T.let(Array.new(@num_groups) do
        Partition.new
      end, T::Array[Partition])

      sorted.each do |timing|
        # loop-based indices
        best_partition_index = -1
        min_time = Float::INFINITY
        min_count_at_min_time = 0

        # look through each partition
        partitions.each_with_index do |partition, index|
          # if the total time in this partition is less than the current minimum
          # partition time, select this as the next partition we use
          if partition.total_time < min_time
            min_time = partition.total_time
            min_count_at_min_time = partition.timings.length
            best_partition_index = index
          elsif partition.total_time == min_time
            if partition.timings.length < min_count_at_min_time
              min_count_at_min_time = partition.timings.length
              best_partition_index = index
            end
          end
        end

        partition = T.must(partitions[best_partition_index])
        partition.timings << timing
        partition.total_time += timing.time
      end

      puts "Total Tests: #{partitions.map { _1.timings.length }.sum}"

      partitions.each_with_index do |p, i|
        puts "  Partition #{i}: #{p.timings.length} tests (#{p.timings.map { _1.time }.sum}s)"
      end

      partitions.map { _1.timings }
    end
  end
end
