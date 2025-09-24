# typed: true

require "open3"
require "rspec"

def bm(label)
  return yield unless ENV["BENCHMARK"]

  require "benchmark"
  res = Benchmark.measure do
    yield
  end

  puts "#{label}: #{res.real}"
end

module TimingRunner
  class Runner
    extend T::Sig

    sig { returns(T::Hash[String, Timing]) }
    attr_accessor :timing_hash

    sig { returns(Partitioner) }
    attr_reader :partitioner

    sig { returns(Config) }
    attr_reader :config

    sig { params(config: Config).void }
    def initialize(config)
      @config = config
      @timing_hash = T.let({}, T::Hash[String, Timing])

      bm("initialize_timings") do
        initialize_timings(config.input_file)
      end

      bm("load_spec_files") do
        load_spec_files
      end

      bm("add_location_to_timings") do
        add_location_to_timings
      end

      bm("validate_timings") do
        validate_timings
      end

      bm("Partitioner.new") do
        @partitioner = Partitioner.new(
          timing_hash.values, config.num_runners
        )
      end
    end

    sig { void }
    def run
      files = files_for(config.runner)

      cmd = ["bundle exec rspec", config.rspec_args, files].compact.join(" ")

      if config.dry_run
        puts "Dry run requested:"

        puts <<~EOF
               Would run
                 #{cmd}

                 Length: #{cmd.length}
             EOF

        return
      end

      # TODO: maybe we can run RSpec directly instead of shelling out? I tried
      # it once but it ended up running all the specs twice and i'm not sure why

      stdin, stdout, stderr, wait_thr = Open3.popen3(cmd)
      stdin.close
      stdout.each { |l| puts l }
      stderr.each { |l| STDERR.puts l }
      wait_thr.join
      stdout.close
      stderr.close
    end

    sig { params(runner: Integer).returns(T::Array[String]) }
    def files_for(runner)
      partition = partitioner.partition_for_group(runner)
      partition.group_by { |timing| T.must(timing.file) }.map do |(file_name, timings)|
        lines = timings.map { _1.id }
        "'#{file_name}[#{lines.join(",")}]'"
      end
    end

    private

    sig { params(timings_file: String).void }
    def initialize_timings(timings_file)
      timings = T.let(Timings.parse_from_file(timings_file), Timings)

      timings.timings.each do |timing|
        existing_timing = @timing_hash[timing.name]

        if existing_timing.nil?
          @timing_hash[timing.name] = timing
        else
          biggest = T.must([existing_timing, timing].max_by { |t| t.time })
          warn "Duplicate timing found for #{timing.name} - choosing the biggest"
          @timing_hash[timing.name] = biggest
        end
      end
    end

    sig { returns(Float) }
    def average_time
      return @average_time if defined?(@average_time)

      @average_time = timing_hash.values.sum(&:time).to_f / timing_hash.values.length
      # we need this to be slightly above 0 so that `array.min` returns different values
      @average_time = 0.0001 if @average_time.nan?

      @average_time
    end

    sig { void }
    def add_location_to_timings
      RSpec.world.example_groups.map do |group|
        group.descendants.map { _1.examples }.flatten.each do |example|
          # group.descendant_filtered_examples.each do |example|
          timing = timing_hash[example.full_description]
          if timing.nil?
            timing_hash[example.full_description] =
              # we initialize these with an average time so that they get grouped
              # into new groups evenly
              Timing.new(
                name: example.full_description,
                time: average_time,
                file: example.metadata[:rerun_file_path],
                line: example.metadata[:line_number],
                id: example.metadata[:scoped_id],
              )
          else
            timing.file = example.metadata[:rerun_file_path]
            timing.line = example.metadata[:line_number]
            timing.id = example.metadata[:scoped_id]
          end
        end
      end
    end

    sig { void }
    def load_spec_files
      require "pry"; binding.pry
      config = RSpec.configuration
      options = RSpec::Core::ConfigurationOptions.new([])
      options.configure(config)
      config.files_or_directories_to_run = [config.default_path]

      config.load_spec_files
    end

    sig { void }
    def validate_timings
      @timing_hash.delete_if do |name, timing|
        if timing.file.nil?
          warn "No location found for test '#{name}' - removing as stale"
          true
        else
          false
        end
      end
    end
  end
end
