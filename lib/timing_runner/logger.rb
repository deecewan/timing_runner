# typed: true

# require "json"
require "rspec"
require "rspec/core/formatters/base_formatter"
require "sorbet-runtime"

require_relative "timings"

module TimingRunner
  class Logger < RSpec::Core::Formatters::BaseFormatter
    extend T::Sig

    RSpec::Core::Formatters.register(self, :start, :example_passed, :start_dump,
                                     :close)

    private

    sig { returns(Timings) }
    attr_reader :timings

    def initialize(io)
      super(io)
      @output = T.let(io, T.any(IO, RSpec::Core::OutputWrapper))
      @timings = Timings.new
    end

    sig do
      params(notification: RSpec::Core::Notifications::ExampleNotification).void
    end

    def example_passed(notification)
      example = notification.example

      timing = Timing.for(example.full_description,
                          example.execution_result.run_time)

      timings.add(timing)
    end

    # stolen from Rspec
    def close(_)
      @output.close if (IO === @output) & (@output != $stdout)
    end

    def start_dump(_)
      case @output
      when File
        timings.dump_to_file(@output)
      else
        @output.write(timings.dump, "\n")
      end
    end
  end
end
