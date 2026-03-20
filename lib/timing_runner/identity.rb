# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module TimingRunner
  module Identity
    extend T::Sig

    OBJECT_ID_PATTERN = /0x[0-9a-f]+/i

    sig do
      params(
        description: String,
        shared_group_names: T::Array[String],
        explicit_key: T.nilable(T.any(String, Symbol))
      ).returns(String)
    end
    def self.for_name(description, shared_group_names: [], explicit_key: nil)
      return "metadata:#{normalize(explicit_key.to_s)}" unless explicit_key.nil?

      normalized_description = normalize(description)
      normalized_shared_groups = shared_group_names.map { normalize(_1) }.uniq.sort

      return normalized_description if normalized_shared_groups.empty?

      [normalized_description, *normalized_shared_groups.map { "shared:#{_1}" }].join("|")
    end

    sig { params(example: T.untyped).returns(String) }
    def self.for_example(example)
      metadata = T.let(example.metadata, T::Hash[Symbol, T.untyped])

      for_name(
        example.full_description,
        shared_group_names: shared_group_names_for(metadata),
        explicit_key: metadata[:timing_runner_key]
      )
    end

    sig { params(value: String).returns(String) }
    def self.normalize(value)
      value.gsub(OBJECT_ID_PATTERN, "0xOBJECT_ID")
    end

    sig { params(metadata: T::Hash[Symbol, T.untyped]).returns(T::Array[String]) }
    def self.shared_group_names_for(metadata)
      Array(metadata[:shared_group_inclusion_backtrace]).filter_map do |frame|
        next unless frame.instance_variable_defined?(:@shared_group_name)

        frame.instance_variable_get(:@shared_group_name).to_s
      end
    end
  end
end
