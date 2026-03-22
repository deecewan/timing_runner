# frozen_string_literal: true

require "fileutils"
require "open3"
require "spec_helper"
require "tmpdir"

RSpec.describe "timing runner integration" do
  REPO_ROOT = File.expand_path("../..", __dir__)

  def bundle_env
    { "BUNDLE_GEMFILE" => File.join(REPO_ROOT, "Gemfile") }
  end

  def run_bundle_command(*command, chdir:)
    stdout, stderr, status = Open3.capture3(bundle_env, *command, chdir:)
    raise <<~ERROR unless status.success?
      Command failed: #{command.join(" ")}
      STDOUT:
      #{stdout}

      STDERR:
      #{stderr}
    ERROR

    [stdout, stderr]
  end

  def run_bundle_command_allow_failure(*command, chdir:)
    Open3.capture3(bundle_env, *command, chdir:)
  end

  def read_labels(path)
    return [] unless File.exist?(path)

    File.readlines(path, chomp: true)
  end

  def clear_file(path)
    File.write(path, "")
  end

  def write_rspec_config(dir, timing_output_path)
    File.write(
      File.join(dir, ".rspec"),
      <<~TEXT
        --require timing_runner
        --format progress
        --format TimingRunner::Logger --out #{timing_output_path}
        --order defined
      TEXT
    )
  end

  def static_usage_spec(results_path)
    <<~RUBY
      RSpec.describe "stable sharding" do
        def record(label)
          File.open(#{results_path.inspect}, "a") { |file| file.puts(label) }
        end

        it "slow alpha" do
          sleep 0.30
          record("slow alpha")
          expect(true).to eq(true)
        end

        it "slow beta" do
          sleep 0.18
          record("slow beta")
          expect(true).to eq(true)
        end

        it "fast gamma" do
          sleep 0.15
          record("fast gamma")
          expect(true).to eq(true)
        end

        it "fast delta" do
          sleep 0.01
          record("fast delta")
          expect(true).to eq(true)
        end
      end
    RUBY
  end

  def dynamic_usage_spec(results_path, include_line_shift_comments:)
    extra_lines = include_line_shift_comments ? "# line shift\n# another line shift\n# one more line shift\n" : ""

    <<~RUBY
      #{extra_lines}
      dynamic_user = Object.new
      keyed_user = Object.new

      RSpec.describe "dynamic sharding" do
        def record(label)
          File.open(#{results_path.inspect}, "a") { |file| file.puts(label) }
        end

        it "dynamic \#{dynamic_user}" do
          sleep 0.30
          record("dynamic")
          expect(true).to eq(true)
        end

        it "keyed \#{keyed_user}", timing_runner_key: "stable-keyed-user" do
          sleep 0.18
          record("keyed")
          expect(true).to eq(true)
        end

        it "fast alpha" do
          sleep 0.15
          record("fast alpha")
          expect(true).to eq(true)
        end

        it "fast beta" do
          sleep 0.01
          record("fast beta")
          expect(true).to eq(true)
        end
      end
    RUBY
  end

  def write_spec(dir, content)
    FileUtils.mkdir_p(File.join(dir, "spec"))
    File.write(File.join(dir, "spec", "usage_spec.rb"), content)
  end

  def capture_timings!(dir, timing_output_path, expected_count: 4)
    run_bundle_command("bundle", "exec", "rspec", chdir: dir)
    expect(File.exist?(timing_output_path)).to eq(true)
    expect(TimingRunner::Timings.parse_from_file(timing_output_path).timings.length).to eq(expected_count)
  end

  def run_shard!(dir, input_file:, runner:, results_path:)
    clear_file(results_path)
    run_bundle_command(
      "bundle", "exec", "timing-runner",
      "--input-file", input_file,
      "--num-runners", "2",
      "--runner", runner.to_s,
      chdir: dir
    )
    read_labels(results_path)
  end

  def dry_run_shard!(dir, input_file:, runner:, num_runners: 2)
    stdout, = run_bundle_command(
      "bundle", "exec", "timing-runner",
      "--input-file", input_file,
      "--num-runners", num_runners.to_s,
      "--runner", runner.to_s,
      "--dry-run",
      chdir: dir
    )
    stdout
  end

  def grouped_usage_spec(results_path)
    <<~RUBY
      RSpec.describe "compressed selectors" do
        def record(label)
          File.open(#{results_path.inspect}, "a") { |file| file.puts(label) }
        end

        context "group a" do
          it "one" do
            sleep 0.30
            record("group a one")
            expect(true).to eq(true)
          end

          it "two" do
            sleep 0.20
            record("group a two")
            expect(true).to eq(true)
          end
        end

        context "group b" do
          it "three" do
            sleep 0.10
            record("group b three")
            expect(true).to eq(true)
          end

          it "four" do
            sleep 0.01
            record("group b four")
            expect(true).to eq(true)
          end
        end
      end
    RUBY
  end

  def fail_after_capture_usage_spec(results_path)
    <<~RUBY
      RSpec.describe "exit status parity" do
        def record(label)
          File.open(#{results_path.inspect}, "a") { |file| file.puts(label) }
        end

        it "will fail on rerun" do
          record("will fail on rerun")
          expect(false).to eq(true)
        end
      end
    RUBY
  end

  def tagged_usage_spec(results_path)
    <<~RUBY
      RSpec.describe "tag filtered sharding" do
        def record(label)
          File.open(#{results_path.inspect}, "a") { |file| file.puts(label) }
        end

        it "regular example" do
          sleep 0.20
          record("regular example")
          expect(true).to eq(true)
        end

        it "release example", :release do
          sleep 0.30
          record("release example")
          expect(true).to eq(true)
        end

        it "second regular example" do
          sleep 0.10
          record("second regular example")
          expect(true).to eq(true)
        end
      end
    RUBY
  end

  it "covers the user workflow of capturing timings and then running shards from them" do
    Dir.mktmpdir do |dir|
      results_path = File.join(dir, "results.log")
      captured_timings = File.join(dir, "captured.log")
      rerun_timings = File.join(dir, "rerun.log")

      write_rspec_config(dir, captured_timings)
      write_spec(dir, static_usage_spec(results_path))

      capture_timings!(dir, captured_timings)

      write_rspec_config(dir, rerun_timings)
      runner_one_labels = run_shard!(dir, input_file: captured_timings, runner: 1, results_path:)
      runner_two_labels = run_shard!(dir, input_file: captured_timings, runner: 2, results_path:)

      expect(runner_one_labels).to contain_exactly("slow alpha", "fast delta")
      expect(runner_two_labels).to contain_exactly("slow beta", "fast gamma")
      expect((runner_one_labels & runner_two_labels)).to eq([])
    end
  end

  it "keeps sharding correctly when line numbers shift and names contain dynamic ids" do
    Dir.mktmpdir do |dir|
      results_path = File.join(dir, "results.log")
      captured_timings = File.join(dir, "captured.log")
      rerun_timings = File.join(dir, "rerun.log")

      write_rspec_config(dir, captured_timings)
      write_spec(dir, dynamic_usage_spec(results_path, include_line_shift_comments: false))

      capture_timings!(dir, captured_timings)

      write_rspec_config(dir, rerun_timings)
      write_spec(dir, dynamic_usage_spec(results_path, include_line_shift_comments: true))

      runner_one_labels = run_shard!(dir, input_file: captured_timings, runner: 1, results_path:)
      runner_two_labels = run_shard!(dir, input_file: captured_timings, runner: 2, results_path:)

      expect(runner_one_labels).to contain_exactly("dynamic", "fast beta")
      expect(runner_two_labels).to contain_exactly("keyed", "fast alpha")
      expect((runner_one_labels & runner_two_labels)).to eq([])
    end
  end

  it "minimizes selector length in dry-run output by collapsing grouped ids" do
    Dir.mktmpdir do |dir|
      results_path = File.join(dir, "results.log")
      captured_timings = File.join(dir, "captured.log")

      write_rspec_config(dir, captured_timings)
      write_spec(dir, grouped_usage_spec(results_path))

      capture_timings!(dir, captured_timings)

      dry_run_output = dry_run_shard!(dir, input_file: captured_timings, runner: 3, num_runners: 3)

      expect(dry_run_output).to include("spec/usage_spec.rb[1:2]")
      expect(dry_run_output).not_to include("spec/usage_spec.rb[1:2:1,1:2:2]")
    end
  end

  it "returns the rspec exit status for the selected shard" do
    Dir.mktmpdir do |dir|
      results_path = File.join(dir, "results.log")
      captured_timings = File.join(dir, "captured.log")

      write_rspec_config(dir, captured_timings)
      write_spec(dir, <<~RUBY)
        RSpec.describe "exit status parity" do
          def record(label)
            File.open(#{results_path.inspect}, "a") { |file| file.puts(label) }
          end

          it "will fail on rerun" do
            record("will fail on rerun")
            expect(true).to eq(true)
          end
        end
      RUBY

      capture_timings!(dir, captured_timings, expected_count: 1)
      write_spec(dir, fail_after_capture_usage_spec(results_path))

      _stdout, _stderr, status = run_bundle_command_allow_failure(
        "bundle", "exec", "timing-runner",
        "--input-file", captured_timings,
        "--num-runners", "1",
        "--runner", "1",
        chdir: dir
      )

      expect(status.exitstatus).to eq(1)
    end
  end

  it "filters partitioned examples using rspec tag arguments" do
    Dir.mktmpdir do |dir|
      results_path = File.join(dir, "results.log")
      captured_timings = File.join(dir, "captured.log")
      rerun_timings = File.join(dir, "rerun.log")

      write_rspec_config(dir, captured_timings)
      write_spec(dir, tagged_usage_spec(results_path))

      capture_timings!(dir, captured_timings, expected_count: 3)

      write_rspec_config(dir, rerun_timings)
      clear_file(results_path)
      run_bundle_command(
        "bundle", "exec", "timing-runner",
        "--input-file", captured_timings,
        "--num-runners", "1",
        "--runner", "1",
        "--", "--tag", "~release",
        chdir: dir
      )

      expect(read_labels(results_path)).to contain_exactly("regular example", "second regular example")
    end
  end

  it "filters partitioned examples using rspec file arguments" do
    Dir.mktmpdir do |dir|
      captured_timings = File.join(dir, "captured.log")
      rerun_timings = File.join(dir, "rerun.log")
      results_path = File.join(dir, "results.log")

      write_rspec_config(dir, captured_timings)
      FileUtils.mkdir_p(File.join(dir, "spec"))
      File.write(
        File.join(dir, "spec", "alpha_spec.rb"),
        <<~RUBY
          RSpec.describe "alpha file" do
            it "alpha example" do
              File.open(#{results_path.inspect}, "a") { |file| file.puts("alpha example") }
              expect(true).to eq(true)
            end
          end
        RUBY
      )
      File.write(
        File.join(dir, "spec", "beta_spec.rb"),
        <<~RUBY
          RSpec.describe "beta file" do
            it "beta example" do
              File.open(#{results_path.inspect}, "a") { |file| file.puts("beta example") }
              expect(true).to eq(true)
            end
          end
        RUBY
      )

      capture_timings!(dir, captured_timings, expected_count: 2)

      write_rspec_config(dir, rerun_timings)
      clear_file(results_path)
      run_bundle_command(
        "bundle", "exec", "timing-runner",
        "--input-file", captured_timings,
        "--num-runners", "1",
        "--runner", "1",
        "--", "spec/alpha_spec.rb",
        chdir: dir
      )

      expect(read_labels(results_path)).to eq(["alpha example"])
    end
  end
end
