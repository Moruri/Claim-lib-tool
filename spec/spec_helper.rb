# frozen_string_literal: true

require 'json'
require 'webmock/rspec'
require_relative '../lib/claim_library'

ROOT = File.expand_path('..', __dir__)

Dir[File.join(__dir__, 'support', '*.rb')].each { |file| require file }

RSpec.configure do |config|
  config.mock_with(:rspec) { |mocks| mocks.verify_partial_doubles = true }
  config.disable_monkey_patching!
  config.expose_dsl_globally = true
end
