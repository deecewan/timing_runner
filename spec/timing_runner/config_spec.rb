# frozen_string_literal: true

require "fileutils"
require "spec_helper"
require "tmpdir"

RSpec.describe TimingRunner::Config do
  def with_env(vars)
    original_env = ENV.to_h
    vars.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
    yield
  ensure
    ENV.replace(original_env)
  end

  describe ".parse_args" do
    it "parses timing-runner options and leaves rspec args after --" do
      config = described_class.parse_args(
        ["--input-file", "timings.log", "--num-runners", "3", "--runner", "2", "--dry-run", "--", "spec/models/user_spec.rb", "--tag", "focus"]
      )

      expect(config).to include(
        input_file: "timings.log",
        num_runners: 3,
        runner: 2,
        dry_run: true,
        rspec_args: ["spec/models/user_spec.rb", "--tag", "focus"]
      )
    end
  end

  describe ".config_file" do
    it "finds the config file in a parent directory" do
      Dir.mktmpdir do |dir|
        root = File.join(dir, "project")
        nested = File.join(root, "spec", "unit")
        FileUtils.mkdir_p(nested)
        config_path = File.join(root, described_class::CONFIG_FILE)
        File.write(config_path, "--input-file\nparent.log\n")

        Dir.chdir(nested) do
          expect(File.realpath(described_class.config_file)).to eq(File.realpath(config_path))
        end
      end
    end
  end

  describe ".load!" do
    it "applies command line, environment, and file config in precedence order" do
      Dir.mktmpdir do |dir|
        File.write(
          File.join(dir, described_class::CONFIG_FILE),
          "--input-file\nfrom-file.log\n--num-runners\n2\n--runner\n1\n"
        )

        with_env(
          "TIMING_RUNNER_INPUT_FILE" => "from-env.log",
          "TIMING_RUNNER_NUM_RUNNERS" => "4",
          "TIMING_RUNNER_RUNNER" => "3"
        ) do
          Dir.chdir(dir) do
            config = described_class.load!(["--input-file", "from-args.log", "--runner", "2"])

            expect(config.input_file).to eq("from-args.log")
            expect(config.num_runners).to eq(4)
            expect(config.runner).to eq(2)
          end
        end
      end
    end

    it "raises SystemExit when required config is missing" do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          expect { described_class.load!([]) }.to raise_error(SystemExit, /exit/)
        end
      end
    end
  end
end
