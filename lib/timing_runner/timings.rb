# typed: strict

require "sorbet-runtime"

module TimingRunner
  class Timing < T::Struct
    extend T::Sig

    const :name, String
    const :time, Float
    const :stable_key, T.nilable(String), default: nil
    prop :file, T.nilable(String)
    prop :line, T.nilable(Integer)
    prop :id, T.nilable(String)

    sig do
      params(name: String, time: Float, stable_key: T.nilable(String))
        .returns(T.attached_class)
    end
    def self.for(name, time, stable_key: nil)
      stable_key = nil if stable_key == name

      new(name:, time:, stable_key:)
    end

    sig { returns(String) }
    def identity
      stable_key || Identity.for_name(name)
    end

    sig { returns(T::Array[String]) }
    def sort_key
      [identity, name]
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
        parts = line.split(SEPERATOR, -1)
        case parts.length
        when 1
          name = T.must(parts[0])
          stable_key = nil
          time = nil
        when 2
          name, time = parts
          stable_key = nil
        when 3
          if float_string?(T.must(parts[1])) && !float_string?(T.must(parts[2]))
            raise CorruptedDataError,
              "line #{line_no} has too many seperators: #{line.gsub(SEPERATOR, "<SEP>")}"
          end

          name, stable_key, time = parts
        else
          raise CorruptedDataError,
            "line #{line_no} has too many seperators: #{line.gsub(SEPERATOR, "<SEP>")}"
        end

        if name.nil? || name.empty?
          raise CorruptedDataError,
            "`name` missing from line #{line_no}: #{line}."
        end
        if !stable_key.nil? && stable_key.empty?
          raise CorruptedDataError,
            "`stable_key` missing from line #{line_no}: #{line}."
        end
        if time.nil? || time.empty?
          raise CorruptedDataError,
            "`time` missing from line #{line_no}: #{line}."
        end
        time = begin
            Float(time)
          rescue ArgumentError
            raise CorruptedDataError,
              "`time` is not a valid float: #{time}. line #{line_no}: #{line}"
          end

        Timing.for(name, time, stable_key:)
      end

      new(timings:)
    end

    sig { params(value: String).returns(T::Boolean) }
    def self.float_string?(value)
      Float(value)
      true
    rescue ArgumentError
      false
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
      timings.map do |timing|
        parts = [timing.name]
        parts << timing.stable_key unless timing.stable_key.nil?
        parts << timing.time.to_s
        parts.join(SEPERATOR)
      end.join("\n")
    end

    sig { params(timing: Timing).void }

    def add(timing)
      timings.push(timing)
    end
  end
end
