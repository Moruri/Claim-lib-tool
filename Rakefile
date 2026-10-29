# frozen_string_literal: true

require 'rspec/core/rake_task'

load File.expand_path('lib/tasks/claim_library.rake', __dir__)

desc 'Run the web app on this machine only. ENV: PORT (default 4567), CONTACT'
task :web do
  require 'rackup'
  Rackup::Server.start(config: File.expand_path('config.ru', __dir__),
                       Host: '127.0.0.1', Port: Integer(ENV.fetch('PORT', 4567)))
end

RSpec::Core::RakeTask.new(:spec)
task default: :spec
