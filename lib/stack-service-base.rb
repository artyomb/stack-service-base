require 'stack-service-base/logging'
require 'stack-service-base/rack_helpers'
require 'stack-service-base/open_telemetry'

module StackServiceBase
  class << self
    def rack_setup app
      # skip if called within Rspec task
      # TODO: warn if called not within Rspec task but with a wrong app class
      return unless app.respond_to? :use

      app.instance_eval do
        RackHelpers.rack_setup app
        if ENV.fetch('PROMETHEUS_METRICS_EXPORT', 'true') == 'true'
          require 'stack-service-base/prometheus'

          # use Rack::Deflater
          use Prometheus::Middleware::Collector
          use Prometheus::Middleware::Exporter
        end

        if OTEL_ENABLED
          otel_initialize app
        end

      end
    end
  end
end