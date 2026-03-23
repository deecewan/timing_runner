# typed: true

require "rspec"

module TimingRunner
  class Verifier
    extend T::Sig

    sig { returns(VerifyConfig) }
    attr_reader :config

    sig { params(config: VerifyConfig).void }
    def initialize(config)
      @config = config
      @loaded_timing_hash = T.let({}, T::Hash[String, Timing])
      @stable_timing_hash =
        T.let(
          Hash.new { |hash, key| hash[key] = [] },
          T::Hash[String, T::Array[Timing]]
        )

      initialize_timings(config.input_file)
      load_spec_files
    end

    sig { returns(Integer) }
    def run
      missing_examples = T.let([], T::Array[String])
      matched_examples = T.let(0, Integer)

      selected_examples.each do |example|
        timing = historical_timing_for(example)

        if timing.nil?
          missing_examples << example.full_description
        else
          matched_examples += 1
        end
      end

      if missing_examples.empty?
        puts "Verification passed: #{matched_examples} selected examples are covered by #{config.input_file}."

        stale_timings = @loaded_timing_hash.length
        puts "Note: #{stale_timings} timing entries were unused." unless stale_timings.zero?

        return 0
      end

      warn "Verification failed: #{missing_examples.length} selected examples are missing from #{config.input_file}:"
      missing_examples.sort.each { |name| warn "  - #{name}" }
      1
    end

    private

    sig { params(timings_file: String).void }
    def initialize_timings(timings_file)
      timings = T.let(Timings.parse_from_file(timings_file), Timings)

      timings.timings.each do |timing|
        existing_timing = @loaded_timing_hash[timing.name]

        if existing_timing.nil?
          @loaded_timing_hash[timing.name] = timing
        else
          biggest = T.must([existing_timing, timing].max_by(&:time))
          warn "Duplicate timing found for #{timing.name} - choosing the biggest"
          @loaded_timing_hash[timing.name] = biggest
        end
      end

      @loaded_timing_hash.each_value do |timing|
        @stable_timing_hash[timing.identity] << timing
      end
    end

    sig { void }
    def load_spec_files
      config = RSpec.configuration
      options = RSpec::Core::ConfigurationOptions.new(rspec_args)
      options.configure(config)

      files_or_directories = config.instance_variable_get(:@files_or_directories_to_run)
      if files_or_directories.nil? || files_or_directories.empty?
        config.files_or_directories_to_run = [config.default_path]
      end

      config.load_spec_files
    end

    sig { returns(T::Array[T.untyped]) }
    def selected_examples
      RSpec.world.example_groups.flat_map(&:descendant_filtered_examples)
    end

    sig { params(example: T.untyped).returns(T.nilable(Timing)) }
    def historical_timing_for(example)
      exact_timing = @loaded_timing_hash[example.full_description]
      return consume_timing(exact_timing) unless exact_timing.nil?

      stable_key = Identity.for_example(example)
      stable_matches = @stable_timing_hash.fetch(stable_key, [])

      case stable_matches.length
      when 0
        nil
      when 1
        consume_timing(T.must(stable_matches.first))
      else
        warn "Ambiguous normalized timing key for '#{example.full_description}' - treating it as missing"
        nil
      end
    end

    sig { params(timing: Timing).returns(Timing) }
    def consume_timing(timing)
      @loaded_timing_hash.delete(timing.name)

      stable_matches = @stable_timing_hash.fetch(timing.identity, [])
      stable_matches.delete(timing)
      @stable_timing_hash.delete(timing.identity) if stable_matches.empty?

      timing
    end

    sig { returns(T::Array[String]) }
    def rspec_args
      config.rspec_args.reject(&:empty?)
    end
  end
end
