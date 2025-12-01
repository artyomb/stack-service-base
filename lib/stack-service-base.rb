require 'stack-service-base/version'
require 'stack-service-base/logging'
require 'stack-service-base/rack_helpers'
require 'stack-service-base/open_telemetry'
require 'stack-service-base/nats_service'
require 'stack-service-base/sinatra_ext'
require 'stack-service-base/debugger'

unless defined? RSpec
  require 'dotenv'
  Dotenv.load '.env.local' if File.exist? '.env.local'
end

module StackServiceBase
  class << self
    def rack_setup app
      # skip if called within Rspec task
      # TODO: warn if called not within Rspec task but with a wrong app class
      return unless app.respond_to? :use

      app.instance_eval do
        if OTEL_ENABLED
          otel_initialize
        end

        if NATS_ENABLED
          initialize_nats_service
        end

        RackHelpers.rack_setup app

        # Sinatra?
        # disable :show_exceptions unless ENV['DEBUG']
        # error do
        #   status 500
        #   $stderr.puts "Exception: #{env['sinatra.error']}"
        #   $stderr.puts "Exception backtrace: #{env['sinatra.error'].backtrace[0..10].join("\n")}"
        #   { error: "Internal server error", message: env['sinatra.error'].message }.to_json
        # end

        if ENV.fetch('PROMETHEUS_METRICS_EXPORT', 'true') == 'true'
          require 'stack-service-base/prometheus'

          # use Rack::Deflater
          use Prometheus::Middleware::Collector
          use Prometheus::Middleware::Exporter
        end

        if defined? Sequel
          require 'stack-service-base/database'

          Sequel::Database.after_initialize { _1.loggers << LOGGER }

          attempts= 10
          sleep_interval= 1

          mod = Module.new do
            define_method(:connect) do |*args, **opts, &blk|
              tries = attempts
              begin
                super(*args, **opts, &blk)
              rescue Sequel::DatabaseConnectionError, Sequel::DatabaseError => e
                if (tries -= 1) > 0
                  LOGGER.warn "DB connect failed (#{e.message}), retrying in #{sleep_interval}s… (#{tries} left)"
                  sleep sleep_interval
                  retry
                end
                raise
              end
            end
          end

          Sequel.singleton_class.prepend(mod)

          require 'sequel/adapters/postgres'
          PG::Connection.singleton_class.prepend(Module.new{
            def connect_to_hosts(*args)
              stack_name = ENV['STACK_NAME'] || 'undefined_stack'
              service_name = ENV['STACK_SERVICE_NAME'] || 'undefined_service'
              args[0][:fallback_application_name] ||= "#{stack_name}_#{service_name}"
              super *args
            end
          })

          require_relative 'stack-service-base/fiber_pool'
        end
      end
    end
  end
end