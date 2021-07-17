# frozen_string_literal: true

require_relative "lib/espn_scraper/version"

Gem::Specification.new do |spec|
  spec.name    = "espn_scraper"
  spec.version = EspnScraper::VERSION
  spec.authors = ["Ivan Kulagin"]
  spec.email   = ["ivan@kulagin.dev"]

  spec.summary               = "espn_scraper"
  spec.description           = "espn_scraper"
  spec.homepage              = "https://github.com/Tgemayel/qd3v"
  spec.required_ruby_version = Gem::Requirement.new('>= 2.7', '< 4')

  spec.metadata["allowed_push_host"] = "TODO: Set to 'http://mygemserver.com'"

  spec.metadata["homepage_uri"]    = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{\A(?:test|spec|features)/}) }
  end

  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency("semantic_logger", "~> 4.7")
  spec.add_dependency("activesupport")
  spec.add_dependency("faraday")
  spec.add_dependency("faraday_middleware")
  spec.add_dependency("nokogiri")

  spec.add_development_dependency("json_expressions")
  spec.add_development_dependency("pry", " 0.14.1")
  spec.add_development_dependency("rake", "~> 13.0")
  spec.add_development_dependency("rspec", "~> 3.0")
  spec.add_development_dependency("rubocop", "~> 1.7")
  spec.add_development_dependency("rubocop-rake", "~> 0.5.1")
  spec.add_development_dependency("rubocop-rspec", "~> 2.3.0")
  spec.add_development_dependency("vcr", "~> 6.0.0")
  spec.add_development_dependency("webmock", "~> 3.13.0")
end
