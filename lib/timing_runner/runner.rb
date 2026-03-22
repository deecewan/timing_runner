# typed: true

require "open3"
require "rspec"
require "shellwords"

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
    SelectorNode = T.type_alias { T::Hash[Symbol, T.untyped] }

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
      @loaded_timing_hash = T.let({}, T::Hash[String, Timing])
      @stable_timing_hash = T.let(
        Hash.new { |hash, key| hash[key] = [] },
        T::Hash[String, T::Array[Timing]]
      )

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

    sig { returns(Integer) }
    def run
      files = files_for(config.runner)
      command = rspec_command(files)
      display_command = format_command_for_display(command)

      if config.dry_run
        puts "Dry run requested:"

        puts <<~EOF
               Would run
                 #{display_command}

                 Length: #{display_command.length}
             EOF

        return 0
      end

      stdin, stdout, stderr, wait_thr = Open3.popen3(*command)
      stdin.close

      stdout_thread = Thread.new { stdout.each { |line| $stdout.print(line) } }
      stderr_thread = Thread.new { stderr.each { |line| STDERR.print(line) } }

      status = wait_thr.value
      stdout_thread.join
      stderr_thread.join
      stdout.close
      stderr.close

      status.exitstatus
    end

    sig { params(runner: Integer).returns(T::Array[String]) }
    def files_for(runner)
      partition = partitioner.partition_for_group(runner)
      all_timings_by_file = timing_hash.values.group_by { T.must(_1.file) }

      partition.group_by { |timing| T.must(timing.file) }.sort_by(&:first).map do |(file_name, timings)|
        selectors = compact_selectors_for_file(
          timings.map { T.must(_1.id) },
          T.must(all_timings_by_file[file_name]).map { T.must(_1.id) }
        )

        if selectors.empty?
          file_name
        else
          "#{file_name}[#{selectors.join(",")}]"
        end
      end
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
          biggest = T.must([existing_timing, timing].max_by { |t| t.time })
          warn "Duplicate timing found for #{timing.name} - choosing the biggest"
          @loaded_timing_hash[timing.name] = biggest
        end
      end

      @loaded_timing_hash.each_value do |timing|
        @stable_timing_hash[timing.identity] << timing
      end
    end

    sig { returns(Float) }
    def average_time
      return @average_time if defined?(@average_time)

      @average_time = @loaded_timing_hash.values.sum(&:time).to_f / @loaded_timing_hash.values.length
      # we need this to be slightly above 0 so that `array.min` returns different values
      @average_time = 0.0001 if @average_time.nan?

      @average_time
    end

    sig { void }
    def add_location_to_timings
      RSpec.world.example_groups.each do |group|
        group.descendant_filtered_examples.each do |example|
          timing_hash[example.full_description] = timing_for_example(example)
        end
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

    sig { void }
    def validate_timings
      @loaded_timing_hash.each_value do |timing|
        warn "No location found for test '#{timing.name}' - removing as stale"
      end
      @loaded_timing_hash.clear
      @stable_timing_hash.clear

      @timing_hash.delete_if do |name, timing|
        if timing.file.nil?
          warn "No location found for test '#{name}' - removing as stale"
          true
        else
          false
        end
      end
    end

    sig { params(example: T.untyped).returns(Timing) }
    def timing_for_example(example)
      historical_timing = historical_timing_for(example)
      metadata = example.metadata

      Timing.for(
        example.full_description,
        historical_timing&.time || average_time,
        stable_key: Identity.for_example(example)
      ).tap do |timing|
        timing.file = metadata[:rerun_file_path]
        timing.line = metadata[:line_number]
        timing.id = metadata[:scoped_id]
      end
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
        warn "Ambiguous normalized timing key for '#{example.full_description}' - falling back to average time"
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

    sig { params(files: T::Array[String]).returns(T::Array[String]) }
    def rspec_command(files)
      args = rspec_args
      args << "--color" if add_color_arg?(args)

      ["bundle", "exec", "rspec", *args, *files]
    end

    sig { returns(T::Array[String]) }
    def rspec_args
      raw_args = config.rspec_args
      return raw_args.reject(&:empty?) if raw_args.is_a?(Array)
      return [] if raw_args.empty?

      Shellwords.split(raw_args)
    end

    sig { params(args: T::Array[String]).returns(T::Boolean) }
    def add_color_arg?(args)
      return false unless $stdout.tty?

      args.none? do |arg|
        arg == "--color" || arg == "--no-color" ||
          arg.start_with?("--color=") || arg.start_with?("--colour")
      end
    end

    sig { params(command: T::Array[String]).returns(String) }
    def format_command_for_display(command)
      command.map { format_arg_for_display(_1) }.join(" ")
    end

    sig { params(arg: String).returns(String) }
    def format_arg_for_display(arg)
      return "'#{arg}'" if arg.include?("[") || arg.include?("]")

      Shellwords.escape(arg)
    end

    sig do
      params(selected_ids: T::Array[String], all_ids: T::Array[String])
        .returns(T::Array[String])
    end
    def compact_selectors_for_file(selected_ids, all_ids)
      selected_ids = selected_ids.uniq.sort_by { scoped_id_sort_key(_1) }
      all_ids = all_ids.uniq.sort_by { scoped_id_sort_key(_1) }

      return [] if selected_ids == all_ids

      tree = build_selector_tree(all_ids, selected_ids.to_h { [_1, true] })

      compact_subtree_selectors(tree, nil)
    end

    sig { params(ids: T::Array[String], selected_lookup: T::Hash[String, T::Boolean]).returns(SelectorNode) }
    def build_selector_tree(ids, selected_lookup)
      root = T.let({ children: {}, total_count: 0, selected_count: 0 }, SelectorNode)

      ids.each do |id|
        current = root
        current[:total_count] = T.must(current[:total_count]) + 1
        current[:selected_count] = T.must(current[:selected_count]) + (selected_lookup.key?(id) ? 1 : 0)

        id.split(":").each do |segment|
          children = T.cast(current[:children], T::Hash[String, SelectorNode])
          child = children[segment] ||= {
            children: {},
            total_count: 0,
            selected_count: 0
          }
          child[:total_count] = T.must(child[:total_count]) + 1
          child[:selected_count] = T.must(child[:selected_count]) + (selected_lookup.key?(id) ? 1 : 0)
          current = child
        end
      end

      root
    end

    sig { params(node: SelectorNode, prefix: T.nilable(String)).returns(T::Array[String]) }
    def compact_subtree_selectors(node, prefix)
      selected_count = T.must(node[:selected_count])
      return [] if selected_count.zero?

      total_count = T.must(node[:total_count])
      children = T.cast(node[:children], T::Hash[String, SelectorNode])
      return [T.must(prefix)] if !prefix.nil? && children.empty?

      child_selectors = children.keys.sort_by { scoped_id_sort_key(_1) }.flat_map do |segment|
        child_prefix = prefix.nil? ? segment : "#{prefix}:#{segment}"
        compact_subtree_selectors(T.must(children[segment]), child_prefix)
      end

      return child_selectors if prefix.nil? || selected_count != total_count

      compressed = [prefix]
      if rendered_selector_length(compressed) <= rendered_selector_length(child_selectors)
        compressed
      else
        child_selectors
      end
    end

    sig { params(ids: T::Array[String]).returns(Integer) }
    def rendered_selector_length(ids)
      ids.join(",").length
    end

    sig { params(scoped_id: String).returns(T::Array[Integer]) }
    def scoped_id_sort_key(scoped_id)
      scoped_id.split(":").map(&:to_i)
    end
  end
end
