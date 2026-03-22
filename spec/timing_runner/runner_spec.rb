# frozen_string_literal: true

require "open3"
require "spec_helper"
require "stringio"
require "tempfile"

RSpec.describe TimingRunner::Runner do
  def build_timing(name, time, file: nil, line: nil, id: nil, stable_key: nil)
    TimingRunner::Timing.new(name:, time:, stable_key:, file:, line:, id:)
  end

  def seed_loaded_timings(runner, timings)
    loaded_timing_hash = timings.to_h { |timing| [timing.name, timing] }
    stable_timing_hash = Hash.new { |hash, key| hash[key] = [] }
    timings.each { |timing| stable_timing_hash[timing.identity] << timing }

    runner.instance_variable_set(:@timing_hash, {})
    runner.instance_variable_set(:@loaded_timing_hash, loaded_timing_hash)
    runner.instance_variable_set(:@stable_timing_hash, stable_timing_hash)
  end

  def seed_current_timings(runner, timings)
    runner.instance_variable_set(:@timing_hash, timings.to_h { |timing| [timing.name, timing] })
  end

  describe "#files_for" do
    it "groups scoped ids by file for the selected runner" do
      runner = described_class.allocate
      partitioner = instance_double(TimingRunner::Partitioner)
      allow(runner).to receive(:partitioner).and_return(partitioner)
      seed_current_timings(
        runner,
        [
          build_timing("first", 1.0, file: "spec/a_spec.rb", id: "1:1"),
          build_timing("second", 1.0, file: "spec/a_spec.rb", id: "1:2"),
          build_timing("third", 1.0, file: "spec/b_spec.rb", id: "1:1")
        ]
      )

      allow(partitioner).to receive(:partition_for_group).with(2).and_return(
        [
          build_timing("first", 1.0, file: "spec/a_spec.rb", id: "1:1"),
          build_timing("second", 1.0, file: "spec/a_spec.rb", id: "1:2"),
          build_timing("third", 1.0, file: "spec/b_spec.rb", id: "1:1")
        ]
      )

      expect(runner.files_for(2)).to eq(
        ["spec/a_spec.rb", "spec/b_spec.rb"]
      )
    end

    it "compresses a fully selected context to its parent scoped id" do
      runner = described_class.allocate
      partitioner = instance_double(TimingRunner::Partitioner)
      allow(runner).to receive(:partitioner).and_return(partitioner)
      seed_current_timings(
        runner,
        [
          build_timing("one", 1.0, file: "spec/a_spec.rb", id: "1:1:1"),
          build_timing("two", 1.0, file: "spec/a_spec.rb", id: "1:1:2"),
          build_timing("three", 1.0, file: "spec/a_spec.rb", id: "1:2:1"),
          build_timing("four", 1.0, file: "spec/a_spec.rb", id: "1:2:2")
        ]
      )

      allow(partitioner).to receive(:partition_for_group).with(1).and_return(
        [
          build_timing("one", 1.0, file: "spec/a_spec.rb", id: "1:1:1"),
          build_timing("two", 1.0, file: "spec/a_spec.rb", id: "1:1:2"),
          build_timing("four", 1.0, file: "spec/a_spec.rb", id: "1:2:2")
        ]
      )

      expect(runner.files_for(1)).to eq(["spec/a_spec.rb[1:1,1:2:2]"])
    end

    it "keeps selectors in a stable numeric order" do
      runner = described_class.allocate
      partitioner = instance_double(TimingRunner::Partitioner)
      allow(runner).to receive(:partitioner).and_return(partitioner)
      seed_current_timings(
        runner,
        [
          build_timing("ten", 1.0, file: "spec/a_spec.rb", id: "1:10:1"),
          build_timing("two", 1.0, file: "spec/a_spec.rb", id: "1:2:1"),
          build_timing("one", 1.0, file: "spec/a_spec.rb", id: "1:1:1")
        ]
      )

      allow(partitioner).to receive(:partition_for_group).with(1).and_return(
        [
          build_timing("ten", 1.0, file: "spec/a_spec.rb", id: "1:10:1"),
          build_timing("two", 1.0, file: "spec/a_spec.rb", id: "1:2:1")
        ]
      )

      expect(runner.files_for(1)).to eq(["spec/a_spec.rb[1:2,1:10]"])
    end
  end

  describe "#run" do
    it "prints the generated command in dry-run mode" do
      runner = described_class.allocate
      config = instance_double(
        TimingRunner::Config,
        runner: 2,
        rspec_args: ["--tag", "focus"],
        dry_run: true
      )
      allow(runner).to receive(:config).and_return(config)
      allow($stdout).to receive(:tty?).and_return(false)

      allow(runner).to receive(:files_for).with(2).and_return(["spec/a_spec.rb[1:1]"])

      expect { expect(runner.run).to eq(0) }
        .to output(/bundle exec rspec --tag focus 'spec\/a_spec\.rb\[1:1\]'/).to_stdout
    end

    it "streams stdout and stderr from rspec execution and returns the exit code" do
      runner = described_class.allocate
      config = instance_double(
        TimingRunner::Config,
        runner: 1,
        rspec_args: "",
        dry_run: false
      )
      allow(runner).to receive(:config).and_return(config)
      allow($stdout).to receive(:tty?).and_return(false)

      stdin = StringIO.new
      stdout = StringIO.new("example output\n")
      stderr = StringIO.new("warning output\n")
      status = instance_double(Process::Status, exitstatus: 7)
      wait_thr = instance_double(Process::Waiter, value: status)

      allow(runner).to receive(:files_for).with(1).and_return(["spec/a_spec.rb[1:1]"])
      allow(STDERR).to receive(:print)
      allow(Open3).to receive(:popen3)
        .with("bundle", "exec", "rspec", "spec/a_spec.rb[1:1]")
        .and_return([stdin, stdout, stderr, wait_thr])

      expect { expect(runner.run).to eq(7) }.to output("example output\n").to_stdout
      expect(STDERR).to have_received(:print).with("warning output\n")
    end

    it "adds --color when stdout is a tty and no color option was provided" do
      runner = described_class.allocate
      config = instance_double(
        TimingRunner::Config,
        runner: 1,
        rspec_args: [],
        dry_run: false
      )
      allow(runner).to receive(:config).and_return(config)
      allow($stdout).to receive(:tty?).and_return(true)

      stdin = StringIO.new
      stdout = StringIO.new
      stderr = StringIO.new
      status = instance_double(Process::Status, exitstatus: 0)
      wait_thr = instance_double(Process::Waiter, value: status)

      allow(runner).to receive(:files_for).with(1).and_return(["spec/a_spec.rb[1:1]"])
      allow(Open3).to receive(:popen3)
        .with("bundle", "exec", "rspec", "--color", "spec/a_spec.rb[1:1]")
        .and_return([stdin, stdout, stderr, wait_thr])

      expect(runner.run).to eq(0)
    end

    it "does not override an explicit no-color option" do
      runner = described_class.allocate
      config = instance_double(
        TimingRunner::Config,
        runner: 1,
        rspec_args: ["--no-color"],
        dry_run: false
      )
      allow(runner).to receive(:config).and_return(config)
      allow($stdout).to receive(:tty?).and_return(true)

      stdin = StringIO.new
      stdout = StringIO.new
      stderr = StringIO.new
      status = instance_double(Process::Status, exitstatus: 0)
      wait_thr = instance_double(Process::Waiter, value: status)

      allow(runner).to receive(:files_for).with(1).and_return(["spec/a_spec.rb[1:1]"])
      allow(Open3).to receive(:popen3)
        .with("bundle", "exec", "rspec", "--no-color", "spec/a_spec.rb[1:1]")
        .and_return([stdin, stdout, stderr, wait_thr])

      expect(runner.run).to eq(0)
    end
  end

  describe "#initialize_timings" do
    it "keeps the largest duplicate timing for the same example" do
      runner = described_class.allocate
      runner.instance_variable_set(:@timing_hash, {})
      runner.instance_variable_set(:@loaded_timing_hash, {})
      runner.instance_variable_set(:@stable_timing_hash, Hash.new { |hash, key| hash[key] = [] })
      separator = TimingRunner::Timings::SEPERATOR

      Tempfile.create("timings") do |file|
        file.write(
          [
            "duplicate example#{separator}1.2",
            "duplicate example#{separator}2.5",
            "unique example#{separator}0.4"
          ].join("\n")
        )
        file.flush

        expect { runner.send(:initialize_timings, file.path) }
          .to output(/Duplicate timing found for duplicate example/).to_stderr

        loaded_timing_hash = runner.instance_variable_get(:@loaded_timing_hash)

        expect(loaded_timing_hash["duplicate example"].time).to eq(2.5)
        expect(loaded_timing_hash["unique example"].time).to eq(0.4)
      end
    end
  end

  describe "#add_location_to_timings" do
    it "updates known timings and creates timings for unseen examples" do
      runner = described_class.allocate
      seed_loaded_timings(runner, [build_timing("existing example", 3.5)])
      allow(runner).to receive(:average_time).and_return(1.25)

      known_example = instance_double(
        "Example",
        full_description: "existing example",
        metadata: { rerun_file_path: "spec/existing_spec.rb", line_number: 12, scoped_id: "1:1" }
      )
      new_example = instance_double(
        "Example",
        full_description: "new example",
        metadata: { rerun_file_path: "spec/new_spec.rb", line_number: 20, scoped_id: "1:2" }
      )
      group = instance_double("ExampleGroup", descendant_filtered_examples: [known_example, new_example])
      world = instance_double("RSpecWorld", example_groups: [group])

      allow(RSpec).to receive(:world).and_return(world)

      runner.send(:add_location_to_timings)

      existing = runner.timing_hash.fetch("existing example")
      expect(existing.file).to eq("spec/existing_spec.rb")
      expect(existing.line).to eq(12)
      expect(existing.id).to eq("1:1")

      new_timing = runner.timing_hash.fetch("new example")
      expect(new_timing.time).to eq(1.25)
      expect(new_timing.file).to eq("spec/new_spec.rb")
      expect(new_timing.line).to eq(20)
      expect(new_timing.id).to eq("1:2")
    end

    it "falls back to a normalized stable key when the exact description changes" do
      runner = described_class.allocate
      old_name = "dynamic #<Object:0x0000abcd>"
      new_name = "dynamic #<Object:0x0000ffff>"
      stable_key = TimingRunner::Identity.for_name(old_name)
      seed_loaded_timings(runner, [build_timing(old_name, 2.0, stable_key:)])

      example = instance_double(
        "Example",
        full_description: new_name,
        metadata: { rerun_file_path: "spec/dynamic_spec.rb", line_number: 42, scoped_id: "1:4" }
      )
      group = instance_double("ExampleGroup", descendant_filtered_examples: [example])
      world = instance_double("RSpecWorld", example_groups: [group])
      allow(RSpec).to receive(:world).and_return(world)

      runner.send(:add_location_to_timings)

      timing = runner.timing_hash.fetch(new_name)
      expect(timing.time).to eq(2.0)
      expect(timing.stable_key).to eq(stable_key)
    end

    it "uses the average time when normalized fallback would be ambiguous" do
      runner = described_class.allocate
      stable_key = TimingRunner::Identity.for_name("dynamic #<Object:0x0000abcd>")
      seed_loaded_timings(
        runner,
        [
          build_timing("dynamic #<Object:0x0000abcd>", 2.0, stable_key:),
          build_timing("dynamic #<Object:0x0000eeee>", 4.0, stable_key:)
        ]
      )
      allow(runner).to receive(:average_time).and_return(1.25)

      example = instance_double(
        "Example",
        full_description: "dynamic #<Object:0x0000ffff>",
        metadata: { rerun_file_path: "spec/dynamic_spec.rb", line_number: 42, scoped_id: "1:4" }
      )
      group = instance_double("ExampleGroup", descendant_filtered_examples: [example])
      world = instance_double("RSpecWorld", example_groups: [group])
      allow(RSpec).to receive(:world).and_return(world)

      expect { runner.send(:add_location_to_timings) }
        .to output(/Ambiguous normalized timing key/).to_stderr

      expect(runner.timing_hash.fetch("dynamic #<Object:0x0000ffff>").time).to eq(1.25)
    end

    it "uses timing_runner_key metadata to match historical timings" do
      runner = described_class.allocate
      seed_loaded_timings(
        runner,
        [build_timing("serializes #<User:0x0000abcd>", 2.0, stable_key: "metadata:serialize-user")]
      )

      example = instance_double(
        "Example",
        full_description: "serializes #<User:0x0000ffff>",
        metadata: {
          rerun_file_path: "spec/serializer_spec.rb",
          line_number: 42,
          scoped_id: "1:4",
          timing_runner_key: "serialize-user"
        }
      )
      group = instance_double("ExampleGroup", descendant_filtered_examples: [example])
      world = instance_double("RSpecWorld", example_groups: [group])
      allow(RSpec).to receive(:world).and_return(world)

      runner.send(:add_location_to_timings)

      timing = runner.timing_hash.fetch("serializes #<User:0x0000ffff>")
      expect(timing.time).to eq(2.0)
      expect(timing.stable_key).to eq("metadata:serialize-user")
    end
  end

  describe "#validate_timings" do
    it "removes stale timings without a discovered file location" do
      runner = described_class.allocate
      runner.instance_variable_set(
        :@loaded_timing_hash,
        { "stale example" => build_timing("stale example", 1.0) }
      )
      runner.instance_variable_set(
        :@stable_timing_hash,
        { "stale example" => [build_timing("stale example", 1.0)] }
      )
      runner.instance_variable_set(
        :@timing_hash,
        {
          "active example" => build_timing("active example", 2.0, file: "spec/active_spec.rb", line: 8, id: "1:1")
        }
      )

      expect { runner.send(:validate_timings) }
        .to output(/No location found for test 'stale example'/).to_stderr

      expect(runner.timing_hash.keys).to eq(["active example"])
    end
  end

  describe "#load_spec_files" do
    it "configures rspec with the user's rspec args before loading files" do
      runner = described_class.allocate
      config_double = instance_double(TimingRunner::Config, rspec_args: ["--tag", "~release", "spec/models"])
      allow(runner).to receive(:config).and_return(config_double)
      config = RSpec.configuration
      options = instance_double(RSpec::Core::ConfigurationOptions)

      allow(RSpec).to receive(:configuration).and_return(config)
      allow(RSpec::Core::ConfigurationOptions).to receive(:new)
        .with(["--tag", "~release", "spec/models"])
        .and_return(options)
      allow(options).to receive(:configure).with(config)
      allow(config).to receive(:instance_variable_get)
        .with(:@files_or_directories_to_run)
        .and_return(["spec/models"])
      allow(config).to receive(:load_spec_files)

      runner.send(:load_spec_files)

      expect(options).to have_received(:configure).with(config)
      expect(config).to have_received(:load_spec_files)
    end

    it "falls back to the default path when rspec args do not specify files" do
      runner = described_class.allocate
      config_double = instance_double(TimingRunner::Config, rspec_args: ["--tag", "~release"])
      allow(runner).to receive(:config).and_return(config_double)
      config = RSpec.configuration
      options = instance_double(RSpec::Core::ConfigurationOptions)

      allow(RSpec).to receive(:configuration).and_return(config)
      allow(RSpec::Core::ConfigurationOptions).to receive(:new)
        .with(["--tag", "~release"])
        .and_return(options)
      allow(options).to receive(:configure).with(config)
      allow(config).to receive(:instance_variable_get)
        .with(:@files_or_directories_to_run)
        .and_return([])
      allow(config).to receive(:default_path).and_return("spec")
      allow(config).to receive(:files_or_directories_to_run=).with(["spec"])
      allow(config).to receive(:load_spec_files)

      runner.send(:load_spec_files)

      expect(config).to have_received(:files_or_directories_to_run=).with(["spec"])
      expect(config).to have_received(:load_spec_files)
    end
  end
end
