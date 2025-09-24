# typed: true

require "colorize"
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

    ConfigError = Class.new(StandardError)
    ParseError = Class.new(StandardError)

    sig { params(args: T::Array[String]).returns(T.attached_class) }
    def load!(args = ARGV)
      env_config = parse_env
      file_config = parse_file
      arg_config = parse_args(args)

      # load order is:
      #   - read from the config file
      #   - read from the environment
      #   - read args from the command line
      config = { dry_run: false }
        .merge(file_config)
        .merge(env_config)
        .merge(arg_config)

      known_props = []

      errors = []
      props.each do |prop, details|
        known_props << prop
        required = !details.has_key?(:default)
        if required && !config.key?(prop)
          errors << "Missing required config: #{prop}"
        elsif !details[:type_object].valid?(config[prop])
          errors << "Invalid type for config: #{prop} (expected #{details[:type_object]}, got #{config[prop].class})"
        end
      end

      unless errors.empty?
        message = "[timing_runner] Configuration errors:\n".red + errors.map { "  - #{_1}" }.join("\n")
        STDERR.puts(message)

        if config[:debug]
          puts "Sources:".blue
          puts "  - From config file (#{CONFIG_FILE}): #{config_file.nil? ? "(not found)".red : file_config.inspect}"
          puts "  - From environment: #{env_config.empty? ? "(not set)".red : env_config.inspect}"
          puts "  - From command line: #{arg_config.inspect}" unless arg_config.empty?
        end

        puts "\nRun `timing-runner --help` for more information.".blue
        exit(1)
      end

      config = config.select { |k, _| known_props.include?(k) }

      new(**T.unsafe(config))
    end

    sig { params(args: T::Array[String]).returns(T::Hash[Symbol, T.untyped]) }
    def parse_args(args)
      options = {}

      found_double_dash = T.let(false, T::Boolean)
      to_process, rspec_args = args.partition do |item|
        if found_double_dash || item == "--"
          found_double_dash = true
          next false
        end

        next true
      end

      rspec_args.shift

      OptionParser.new do |parser|
        parser.banner = "Usage:".blue + " timing-runner " + "[options] ".white + "[-- [rspec args]]\n".light_black

        parser.on("-h", "--help", "Show this help message") do
          puts parser
          exit
        end

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

        parser.on("--[no-]debug", Integer,
                  "Print debug output from the configuration") do |d|
          options[:debug] = d.nil?
        end

        parser.on("--color [VALUE]", [:always, :auto, :never], "When to use colors (always, auto, never)") do |d|
          if d == :always
            String.disable_colorization = false
          elsif d == :never
            String.disable_colorization = true
          end
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
        config_key = k.gsub(/^TIMING_RUNNER_/, "--").downcase.gsub("_", "-")

        [config_key, v]
      end.flatten

      return {} if args.empty?

      parse_args(args)
    end

    # naively search up until we find a config file
    sig { returns(T.nilable(String)) }
    def config_file
      path = Pathname.new(Dir.pwd)

      while path != path.parent
        return (path + CONFIG_FILE).to_s if (path + CONFIG_FILE).exist?

        path = path.parent
      end
    end
  end
end
