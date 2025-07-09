require 'stack-service-base/logging'
require 'stack-service-base/rack_helpers'
require 'stack-service-base/open_telemetry'
require 'stack-service-base/nats_service'

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
          # ---
          #
          require_relative 'stack-service-base/fiber_pool'
        end
      end
    end
  end
end