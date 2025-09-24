# typed: strict

require "sorbet-runtime"

module TimingRunner
  class Timing < T::Struct
    extend T::Sig

    const :name, String
    const :time, Float
    prop :file, T.nilable(String)
    prop :line, T.nilable(Integer)
    prop :id, T.nilable(String)

    sig { params(name: String, time: Float).returns(T.attached_class) }
    def self.for(name, time)
      new(name:, time:)
    end

    sig { returns(String) }

    def location
      "#{T.must(file)}:#{T.must(line)}"
    end
  end

  class Timings < T::Struct
    CorruptedDataError = Class.new(StandardError)

    extend T::Sig

    const :timings, T::Array[Timing], default: []

    # a utf-8 seperator character that is unlikely to be used
    SEPERATOR = "\u{1D}"

    sig { params(file_name: String).returns(T.attached_class) }
    def self.parse_from_file(file_name)
      contents = File.exist?(file_name) ? File.read(file_name) : ""

      parse(contents)
    end

    sig { params(content: String).returns(T.attached_class) }
    def self.parse(content)
      timings = content.split("\n").each_with_index.map do |line, index|
        line_no = index + 1
        name, time = line.split(SEPERATOR)
        if name.nil?
          raise CorruptedDataError,
            "`name` missing from line #{line_no}: #{line}."
        end
        if time.nil?
          raise CorruptedDataError,
            "`time` missing from line #{line_no}: #{line}."
        end
        if time.include?(SEPERATOR)
          raise CorruptedDataError,
            "line #{line_no} has too many seperators: #{line.gsub(SEPERATOR, "<SEP>")}"
        end
        time = begin
            Float(time)
          rescue ArgumentError
            raise CorruptedDataError,
              "`time` is not a valid float: #{time}. line #{line_no}: #{line}"
          end

        Timing.for(name, time)
      end

      new(timings:)
    end

    sig { params(file: File, lock: T::Boolean).void }

    def dump_to_file(file, lock: false)
      begin
        file.flock File::LOCK_EX if lock
        file.write(dump)
      ensure
        file.flock File::LOCK_UN
      end
    end

    sig { returns(String) }

    def dump
      timings.map { [_1.name, SEPERATOR, _1.time].join("") }.join("\n")
    end

    sig { params(timing: Timing).void }

    def add(timing)
      timings.push(timing)
    end
  end
end
