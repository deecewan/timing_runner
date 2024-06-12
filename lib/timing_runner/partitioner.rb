# typed: true

module TimingRunner
  class Partitioner
    extend T::Sig

    TimingArray = T.type_alias { T::Array[Timing] }
    NestedTimings = T.type_alias { T::Array[TimingArray] }

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
      groups = T.let(
        Array.new(@num_groups) { [] },
        NestedTimings,
      )
      group_timing = Array.new(@num_groups, 0.0)
      total_time = 0.0

      # sort first so we get a stable order
      timings.sort_by {|t| T.must(t.location)}
        .take(@num_groups).each_with_index do |timing, index|
          T.must(groups[index]) << timing
          group_timing[index] += timing.time
          total_time += timing.time
        end

      timings.drop(@num_groups).each do |timing|
        add_to_index = T.must(group_timing.index(group_timing.min))

        T.must(groups[add_to_index]) << timing
        group_timing[add_to_index] += timing.time
        total_time += timing.time
      end

      expected_average = total_time / @num_groups

      groups
    end
  end
end
