# frozen_string_literal: true

require_relative "lib/yahoo_finance_client/version"

Gem::Specification.new do |spec|
  spec.name = "yahoo_finance_client"
  spec.version = YahooFinanceClient::VERSION
  spec.authors = ["Francesc Leveque"]
  spec.email = ["francesc.leveque@gmail.com"]

  spec.summary = "Basic Yahoo! Finance API client"
  spec.description = "Basic Yahoo! Finance API client to support the Dividend Portfolio pet project"
  spec.homepage = "https://github.com/fleveque/dividend-portfolio"
  spec.license = "GPL-3.0"
  spec.required_ruby_version = ">= 3.4.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["bug_tracker_uri"] = "https://github.com/fleveque/yahoo_finance_client/issues"
  spec.metadata["source_code_uri"] = "https://github.com/fleveque/yahoo_finance_client"
  spec.metadata["changelog_uri"] = "https://github.com/fleveque/yahoo_finance_client/blob/master/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "httparty", "~> 0.21.0"
  spec.add_dependency "csv"
end
