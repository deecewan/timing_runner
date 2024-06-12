# typed: true

require "open3"
require "rspec"

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
      @without_timing = []
      @timing_hash = T.let({}, T::Hash[String, Timing])

      initialize_timings(config.input_file)

      load_spec_files

      add_location_to_timings

      validate_timings

      @partitioner = Partitioner.new(
        timing_hash.values, config.num_runners
      )
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
      partitioner.partition_for_group(runner).map { |t| T.must(t.location) }
    end

    private

    sig { params(timings_file: String).void }
    def initialize_timings(timings_file)
      @to_remove = []

      timings = T.let(Timings.parse_from_file(timings_file), Timings)

      timings.timings.each do |timing|
        if @timing_hash[timing.name].nil?
          @timing_hash[timing.name] = timing
        else
          warn "Duplicate timing found for #{timing.name} - ignoring"
          @to_remove << timing.name
        end
      end

      @to_remove.each do |to_remove|
        @timing_hash.delete(to_remove)
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

    def add_location_to_timings
      RSpec.world.example_groups.map do |group|
        group.examples.each do |example|
          timing = timing_hash[example.full_description]
          if timing.nil?
            @without_timing << example
            timing_hash[example.full_description] =
              # we initialize these with an average time so that they get grouped
              # into new groups evenly
              Timing.new(
                name: example.full_description,
                time: average_time,
                location: example.location,
              )
          else
            timing.location = example.location
          end
        end
      end
    end

    def load_spec_files
      config = RSpec.configuration
      options = RSpec::Core::ConfigurationOptions.new([])
      options.configure(config)
      config.files_or_directories_to_run = [config.default_path]

      config.load_spec_files
    end

    def validate_timings
      @timing_hash.delete_if do |name, timing|
        if timing.location.nil?
          warn "No location found for test '#{name}' - removing as stale"
          true
        else
          false
        end
      end
    end
  end
end
