module StackServiceBase
  class << self
    def rack_setup app
      # skip if called within Rspec task
      # TODO: warn if called not within Rspec task but with a wrong app class
      return unless app.respond_to? :use

      app.instance_eval do
        if ENV.fetch('PROMETHEUS_METRICS_EXPORT', 'true') == 'true'
          require 'stack-service-base/prometheus'

          # use Rack::Deflater
          use Prometheus::Middleware::Collector
          use Prometheus::Middleware::Exporter
        end
      end
    end
  end
end