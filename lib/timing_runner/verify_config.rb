# typed: true

require "optparse"
require "sorbet-runtime"

class TimingRunner::VerifyConfig < T::Struct
  extend T::Sig

  const :input_file, String
  const :rspec_args, T::Array[String], default: []

  class << self
    extend T::Sig

    sig { params(args: T::Array[String]).returns(T.attached_class) }
    def load!(args = ARGV)
      options = parse_args(args)

      errors = []
      props.each do |prop, details|
        required = !details.has_key?(:default)
        if required && !options.key?(prop)
          errors << "Missing required config: #{prop}"
        elsif options.key?(prop) && !details[:type_object].valid?(options[prop])
          errors << "Invalid type for config: #{prop} (expected #{details[:type_object]}, got #{options[prop].class})"
        end
      end

      unless errors.empty?
        STDERR.puts(
          "[timing_runner] Verification configuration errors:\n" \
            "#{errors.map { "  - #{_1}" }.join("\n")}"
        )
        STDERR.puts("\nRun `timing-runner verify --help` for more information.")
        exit(1)
      end

      new(**T.unsafe(options))
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

        true
      end

      rspec_args.shift

      OptionParser.new do |parser|
        parser.banner =
          "Usage: timing-runner verify [options] [-- [rspec args]]"

        parser.on("-h", "--help", "Show this help message") do
          puts parser
          exit
        end

        parser.on(
          "-i", "--input-file FILE",
          "The timing file to verify against the current RSpec selection"
        ) do |file|
          options[:input_file] = file
        end
      end.parse!(to_process)

      options.merge(rspec_args:)
    end
  end
end
