require 'stack-service-base/logging'
require 'rspec-benchmark'
require 'rack/test'
require 'async/rspec'
require 'rack/builder'
require "rspec/snapshot"
require 'testcontainers'

module Rack::Test::AppHelper
  def app = RSpec.configuration.app
end

RSpec.configure do |config|
  config.include Rack::Test::AppHelper, type: :request
  config.include Rack::Test::Methods, type: :request
  config.include RSpec::Benchmark::Matchers
  config.include RSpec::Snapshot
  config.include_context Async::RSpec::Reactor
  config.add_setting :app
  config.add_setting :pg_container

  # Tag anything under /integration as :integration
  # config.define_derived_metadata(file_path: %r{/spec/integration/}) { |m| m[:type] = :integration }

  # ensure this only runs for request specs; avoid leaking into other types
  config.before(type: :request) do
    header 'Host', 'localhost'
  end

  # Load Rack app only once when first integration test runs
  config.before(:suite) do
    if RSpec.world.filtered_examples.values.flatten.any? { |e| e.metadata[:type] == :request }
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
      rack_app, = Rack::Builder.parse_file(File.expand_path("../../config.ru", __dir__))
      RSpec.configuration.app = rack_app
    end
  end

  config.after(:suite) do
    return unless RSpec.configuration.pg_container
    RSpec.configuration.pg_container.stop
    RSpec.configuration.pg_container.delete
  end
end
