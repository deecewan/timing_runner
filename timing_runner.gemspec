# frozen_string_literal: true

require_relative "lib/timing_runner/version"

Gem::Specification.new do |spec|
  spec.name = "timing_runner"
  spec.version = TimingRunner::VERSION
  spec.authors = ["David Buchan-Swanson"]
  spec.email = ["david.buchanswanson@gmail.com"]

  spec.summary = "split specs per example, based on time"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  # spec.metadata["allowed_push_host"] = "TODO: Set to your gem server 'https://example.com'"

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .circleci appveyor])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"
  spec.add_dependency "pry"
  spec.add_dependency "rspec"
  spec.add_dependency "sorbet-runtime"
  spec.add_dependency "colorize", "~> 1.1"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
  spec.metadata["rubygems_mfa_required"] = "true"
end
