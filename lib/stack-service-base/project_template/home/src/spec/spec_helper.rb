# frozen_string_literal: true
$VERBOSE = nil

require 'stack-service-base/logging'
require 'rspec-benchmark'
require 'rack/test'
require 'async/rspec'
require 'rack/builder'
require "rspec/snapshot"
require 'testcontainers'
require 'simplecov'
SimpleCov.start

#ENV['DB_URL'] = 'sqlite::memory:'

module Rack::Test::JHelpers
  def app = RSpec.configuration.app
end

RSpec.configure do |config|
  config.include Rack::Test::Methods
  config.include Rack::Test::JHelpers
  config.include RSpec::Benchmark::Matchers
  config.include RSpec::Snapshot
  config.include_context Async::RSpec::Reactor
  config.add_setting :pg_container
  config.add_setting :app

  config.before(:each) do
    header 'Host', 'localhost'
  end

  config.before(:suite) do
    db_url = ENV['TEST_DB_URL']
    if db_url.nil?
      pg_container = Testcontainers::DockerContainer
                       .new("postgis/postgis:16-3.4")
                       .with_exposed_port(5432)
                       .with_env("POSTGRES_USER", "test")
                       .with_env("POSTGRES_PASSWORD", "test")
                       .with_env("POSTGRES_DB", "app_test")
      pg_container.logger = LOGGER
      pg_container.add_wait_for(:logs, /database system is ready to accept connections/)
      RSpec.configuration.pg_container = pg_container
      pg_container.start
      db_url = "postgres://test:test@#{pg_container.host}:#{pg_container.first_mapped_port}/app_test"
    end
    ENV['DB_URL'] = db_url
    ENV['APP_ENV'] = "test"
    RSpec.configuration.app = Rack::Builder.parse_file(File.expand_path('config.ru'))
  end

  config.after(:suite) do
    return unless RSpec.configuration.pg_container
    RSpec.configuration.pg_container.stop
    RSpec.configuration.pg_container.delete
  end
end
