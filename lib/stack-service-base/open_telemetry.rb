require 'async'

ENV['OTEL_LOG_LEVEL'] ||= 'debug'
ENV['OTEL_TRACES_EXPORTER'] ||= 'console,otlp'
ENV['OTEL_LOGS_EXPORTER'] ||= 'otlp,console'

class Otel
  class << self
    attr_accessor :enabled # To temporally disable Otel
  end
end

unless defined? OTEL_ENABLED
  OTEL_ENABLED = !ENV['OTEL_EXPORTER_OTLP_ENDPOINT'].to_s.empty?
end

Otel.enabled = OTEL_ENABLED

$stdout.puts "OTEL_ENABLED: #{OTEL_ENABLED}"

# require 'async'
# require 'grape'

if OTEL_ENABLED
  STACK_NAME = ENV['STACK_NAME'] || 'undefined_stack'
  SERVICE_NAME = ENV['STACK_SERVICE_NAME'] || 'undefined_service'
  HOSTNAME=ENV['HOSTNAME'] || 'undefined'
  ENV['OTEL_RESOURCE_ATTRIBUTES'] ||= "deployment.environment=#{STACK_NAME},service.name=#{SERVICE_NAME},hostname=#{HOSTNAME}"
  ENV.select{ |k,v| k =~ /OTEL/}.each { |k,v| $stdout.puts "#{k}: #{v}"}

  require 'opentelemetry/sdk'
  require 'opentelemetry/exporter/otlp'
  require 'opentelemetry/instrumentation/all'
  require 'opentelemetry-api'
  require 'opentelemetry-sdk'
  require 'opentelemetry-logs-sdk'
  require 'opentelemetry-exporter-otlp-logs'
end

if false
  # TODO: disable Faraday spans for the given Threads
  #   debug and test

  if defined? OpenTelemetry::Instrumentation::Faraday::Middlewares::Stable::TracerMiddleware
    class OpenTelemetry::Instrumentation::Faraday::Middlewares::Stable::TracerMiddlewareTracerMiddleware
      alias_method :_original_call, :call
      def call(env)
        if Thread.current[:disable_faraday] == true
          app.call env
        else
          _original_call(env)
        end
      end
    end
  end

end

if defined? Async and OTEL_ENABLED
  module AsyncTaskOTELPatch
    def initialize(*pos, **kw, &block)
      ctx_ = OpenTelemetry::Context.current

      block_otl = ->(t, *arguments){
        OpenTelemetry::Context.with_current(ctx_) do
          block.call t, *arguments
        end
      }
      super(*pos, **kw, &block_otl)
    end
  end

  Async::Task.prepend AsyncTaskOTELPatch
end

def flatten_hash(hash, path = [], result = {})
  hash.each do |k, v|
    path += [k]
    result[path.join('.')] = v.to_s if v.is_a?(String) || v.is_a?(Numeric)
    flatten_hash(v, path, result) if v.is_a?(Hash) || v.is_a?(Array)
    path.pop
  end
  result
end

if defined? LOGGER and OTEL_ENABLED
  OpenTelemetry.logger = LOGGER
end

def otel_initialize
  $stdout.puts "otl_configure: OTEL_ENABLED: #{OTEL_ENABLED}"
  return unless OTEL_ENABLED

  OpenTelemetry::SDK.configure do |c|
    OpenTelemetry::Instrumentation::Rack
    # OpenTelemetry::Instrumentation::Rack::Middlewares::TracerMiddleware
    # Rack::Builder
    OpenTelemetry::Instrumentation::Sinatra
    c.use_all({
      'OpenTelemetry::Instrumentation::Sinatra' => { install_rack: false }, # installed by rack-helpers.rb#176
      'OpenTelemetry::Instrumentation::Rack' => {
        use_rack_events: false, # TODO: doesnt work with Websoket requests
        # /home/user/.rbenv/versions/3.3.1/lib/ruby/gems/3.3.0/gems/opentelemetry-instrumentation-rack-0.26.0/lib/opentelemetry/instrumentation/rack/instrumentation.rb#43
        url_quantization: ->(path, env) { "HTTP #{env['REQUEST_METHOD']} #{path}" },
        untraced_requests: ->(env) { env['HTTP_UPGRADE'] == 'websocket' }
      }
    })
    # c.service_name = SERVICE_NAME
  end

  # Logs API
  # ENV['OTEL_LOGS_EXPORTER'] = 'otlp,console' # Export logs to the console ,console
  if ENV['OTEL_LOGS_EXPORTER'] =~ /console/
    processor = OpenTelemetry::SDK::Logs::Export::SimpleLogRecordProcessor.new(OpenTelemetry::SDK::Logs::Export::ConsoleLogRecordExporter.new)
    OpenTelemetry.logger_provider.add_log_record_processor(processor)
  end

  # Access a Logger for your library from the LoggerProvider configured by the OpenTelemetry API
  logger = OpenTelemetry.logger_provider.logger(name: SERVICE_NAME, version: '0.1.0')
  logger.on_emit( timestamp: Time.now, severity_text: 'INFO', body: 'Log provider initialized ', attributes: { 'ready' => true } )

  at_exit do
    OpenTelemetry.tracer_provider.force_flush
    OpenTelemetry.tracer_provider.shutdown
    OpenTelemetry.logger_provider.shutdown
  end

  $tracer_ = OpenTelemetry.tracer_provider.tracer(SERVICE_NAME)

  otl_span "#{SERVICE_NAME} start", {
    'stack.name': ENV['STACK_NAME'],
    'stack.service.name': ENV['STACK_SERVICE_NAME'],
    'org.opencontainers.image.title': ENV['ORG_OPENCONTAINERS_IMAGE_TITLE'],
    'org.opencontainers.image.url':  ENV['ORG_OPENCONTAINERS_IMAGE_URL'],
    'org.opencontainers.image.source': ENV['ORG_OPENCONTAINERS_IMAGE_SOURCE'],
    'org.opencontainers.image.created': ENV['ORG_OPENCONTAINERS_IMAGE_CREATED'],
    'com.gitlab.ci.commt.timestamp': ENV['COM_GITLAB_CI_COMMIT_TIMESTAMP'],
    'com.gitlab.ci.tag': ENV['COM_GITLAB_CI_TAG'],
    RACK_ENV: ENV['RACK_ENV'],
    NODE_ENV: ENV['NODE_ENV'],
    SERVER_ENV: ENV['SERVER_ENV'],
  } do |span|

    span.add_event("not-working in kibana APM", attributes:{
      event: 'Success',
      message: 'Get data from elastic Success'
    }.transform_keys(&:to_s) )
    # span.status = OpenTelemetry::Trace::Status.error("error message here!")
  end
end

if defined? Sequel and OTEL_ENABLED
  class Sequel::Database
    alias old_test_connection test_connection

    def test_connection(...)
      OpenTelemetry::Common::Utilities.untraced do
        old_test_connection(...)
      end
    end

    alias old_valid_connection? valid_connection?
    def valid_connection?(...)
      OpenTelemetry::Common::Utilities.untraced do
        old_valid_connection?(...)
      end
    end
  end
end


# Thread.otl_new do
# ...
# end

class << Thread
  alias_method :_otel_original_new, :new

  if OTEL_ENABLED
    def otl_new(*args, **kwargs, &block)
      ctx = OpenTelemetry::Context.current

      _otel_original_new(*args, **kwargs) do |*bargs|
        OpenTelemetry::Context.with_current(ctx) do
          block.call(*bargs)
        end
      end
    end
  else
    alias_method :otl_new, :new
  end
end

def otl_span_thread(name, attributes = {}, &block)
  ctx_ = OpenTelemetry::Context.current
  Thread.new do
    OpenTelemetry::Context.with_current(ctx_) do
      otl_span(name, attributes, &block)
    end
  end
end

def otl_span(name, attributes = {}, &block)
  # span_ = OpenTelemetry::Trace.current_span
  return yield(nil) unless OTEL_ENABLED && Otel.enabled

  return yield(nil) unless $tracer_
  $tracer_&.in_span(name, attributes: flatten_hash(attributes.transform_keys(&:to_s).transform_values{_1 || 'n/a'}) ) do |span|
    yield span
  end
end

# otl_current_span { _1.def add_attributes(otl_traceparent_id: otl_traceparent_id) }
def otl_current_span
  return unless OTEL_ENABLED && Otel.enabled
  yield OpenTelemetry::Trace.current_span
end

# OpenTelemetry::Trace.current_span.tap do |span|
#   span.record_exception(e)
#   span.status = OpenTelemetry::Trace::Status.error("Unhandled exception of type: #{e.class}")
# end

def otl_traceparent_id
  return nil unless OTEL_ENABLED && Otel.enabled

  span_context = OpenTelemetry::Trace.current_span.context
  trace_id = span_context.hex_trace_id
  span_id = span_context.hex_span_id
  trace_flags = span_context.trace_flags.sampled? ? '01' : '00'
  "00-#{trace_id}-#{span_id}-#{trace_flags}"
end

def otl_span_from_traceparent(traceparent_id, name, attributes = {})
  parent_ctx = OpenTelemetry.propagation.extract( 'traceparent' => traceparent_id )

  OpenTelemetry::Context.with_current(parent_ctx) do
    otl_span(name, attributes) do |span|
      yield span if block_given?
    end
  end
end

def otl_def(name)
  original_method = self.respond_to?(:instance_method) ? instance_method(name) : method(name)
  self.respond_to?(:remove_method) ? remove_method(name) : Object.send(:remove_method, name)
  original_method = original_method.respond_to?(:unbind) ? original_method.unbind : original_method

  define_method(name) do |*args, **kwargs, &block|
    klass = self.respond_to?(:class_name) ? self.class_name : (self.respond_to?(:name) ? self.name : 'main')
    otl_span("method: #{klass}.#{name}", {args: args.to_s, kwargs: kwargs.to_s}) do |span|
      original_method.bind(self).call(*args, **kwargs, &block)
    end
  end
end

if OTEL_ENABLED
  class OpenTelemetry::SDK::Trace::Span
    alias add_attributes_old add_attributes

    def add_attributes(attributes)
      add_attributes_old flatten_hash attributes
                           .transform_keys(&:to_s)
                           .transform_values{ _1 || 'n/a' }
    end
  end
end

if defined? Safrano::Request and OTEL_ENABLED
  require 'odata/error'

  class Safrano::Request
    def process
      begin
        @response = Safrano::Response.new
        before.tap_error { |err| dispatch_error(err) }
              .tap_valid { |_res| dispatch }

      rescue Sequel::Error => e
        OpenTelemetry::Trace.current_span.tap do |span|
          span.record_exception(e)
          span.status = OpenTelemetry::Trace::Status.error("Unhandled exception of type: #{e.class}")
        end
        dispatch_error(Safrano::SequelExceptionError.new(e))
      end
      @response.finish
    end
  end
end

