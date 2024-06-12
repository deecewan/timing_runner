# typed: true

require "optparse"
require "sorbet-runtime"

class TimingRunner::Config < T::Struct
  CONFIG_FILE = ".timing-runner"

  extend T::Sig

  const :input_file, String
  const :num_runners, Integer
  const :rspec_args, T.any(String, T::Array[T.untyped]), default: ""
  const :dry_run, T::Boolean, default: false
  const :runner, Integer

  class << self
    extend T::Sig

    ParseError = Class.new(StandardError)

    sig { params(args: T::Array[String]).returns(T.attached_class) }
    def load!(args = ARGV)
      env_config = parse_env
      file_config = parse_file
      arg_config = parse_args(args)

      # command line args take precedence
      config = {dry_run: false}.merge(env_config).merge(file_config).merge(arg_config)

      # sorbet doesn't know this hash will contain everything we need
      # and if it doesn't, we can't know until runtime
      # so, we'll settle for a runtime error
      new(**T.unsafe(config))
    end

    sig {params(args: T::Array[String]).returns(T::Hash[Symbol, T.untyped])}
    def parse_args(args)
      options = {}

      found_double_dash = T.let(false, T::Boolean)
      to_process, rspec_args = args.partition do |item|
        if found_double_dash
          next false
        end
        if item == '--'
          found_double_dash = true
          next false
        end

        next true
      end

      rspec_args.shift

      OptionParser.new do |parser|
        parser.on("-i", "--input-file FILE",
          "The file where the timings are located") do |f|
            options[:input_file] = f
          end

        parser.on("-n", "--num-runners RUNNERS", Integer,
          "How many runners there will be") do |n|
            options[:num_runners] = n
          end

        parser.on("-r", "--runner RUNNER", Integer,
          "The runner to run tests for") do |n|
            options[:runner] = n
          end

        parser.on(
          "-d", "--[no-]dry-run",
          "If dry-run is set, the command will be printed instead of executed"
        ) do |d|
            options[:dry_run] = d
          end
      end.parse!(to_process)

      options.merge(rspec_args:)
    end

    def parse_file
      file = config_file
      return {} if file.nil?

      parse_args(File.read(file).split("\n"))
    end

    def parse_env
      args = ENV.select { |k| k.start_with?("TIMING_RUNNER") }.map do |k, v|
        # convert the key into a format that OptParse will understand
        config_key = k.gsub(/^TIMING_RUNNER_/, '--').downcase.gsub('_', '-')

        [config_key, v]
      end.flatten

      parse_args(args)
    end

    # naively search up until we find a config file
    sig { returns(T.nilable(String))}
    def config_file
      path = Pathname.new(Dir.pwd)

      while path != path.parent
        return (path + CONFIG_FILE).to_s if (path + CONFIG_FILE).exist?

        path = path.parent
      end
    end
  end
end
