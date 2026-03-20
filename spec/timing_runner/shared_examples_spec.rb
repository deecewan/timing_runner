# frozen_string_literal: true

require "json"
require "open3"
require "spec_helper"

RSpec.describe "shared example integration" do
  def shared_example_metadata
    script = <<~RUBY
      require "json"
      require "rspec"

      shared_examples "common behavior" do |label|
        it("shared behaves \#{label}") { expect(true).to eq(true) }
      end

      RSpec.describe "outer" do
        include_examples "common behavior", "from include"

        context "nested" do
          include_examples "common behavior", "from nested include"
        end
      end

      examples = RSpec.world.example_groups.flat_map do |group|
        group.descendants.flat_map(&:examples)
      end

      puts JSON.generate(examples.map { |example|
        {
          "full_description" => example.full_description,
          "scoped_id" => example.metadata[:scoped_id],
          "rerun_file_path" => example.metadata[:rerun_file_path],
          "line_number" => example.metadata[:line_number],
          "shared_group_names" => example.metadata.fetch(:shared_group_inclusion_backtrace, []).map { |frame|
            frame.instance_variable_get(:@shared_group_name)
          }
        }
      })
    RUBY

    stdout, stderr, status = Open3.capture3("bundle exec ruby", stdin_data: script)
    raise stderr unless status.success?

    JSON.parse(stdout)
  end

  it "gives shared example inclusions distinct full descriptions" do
    descriptions = shared_example_metadata.map { |example| example.fetch("full_description") }

    expect(descriptions).to include(
      a_string_matching(/shared behaves from include/),
      a_string_matching(/shared behaves from nested include/)
    )
    expect(descriptions.uniq).to eq(descriptions)
  end

  it "reports shared example metadata that can be mapped back onto timings" do
    metadata = shared_example_metadata

    expect(metadata.map { |example| example.fetch("shared_group_names") }).to all(eq(["common behavior"]))
    expect(metadata.map { |example| example.fetch("scoped_id") }.uniq.length).to eq(metadata.length)
    expect(metadata.map { |example| example.fetch("rerun_file_path") }.uniq).to eq(["-"])
    expect(metadata.map { |example| example.fetch("line_number") }).to all(eq(5))
  end
end
