# frozen_string_literal: true

require "espn_scraper"
require "vcr"
require "json_expressions/rspec"

# LOGGING

logs_dir = File.expand_path(File.join(__dir__, "..", "log"))
log_file = File.join(logs_dir, "test.log")

Dir.mkdir(logs_dir) unless Dir.exist?(logs_dir)
# File.unlink(log_file) if File.exists?(log_file)

SemanticLogger.default_level = :debug
SemanticLogger.add_appender(file_name: log_file)

# CONFIG

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with(:rspec) do |c|
    c.syntax = :expect
  end
end

VCR.configure do |config|
  config.cassette_library_dir = "fixtures/vcr_cassettes"
  config.hook_into(:webmock)
end
