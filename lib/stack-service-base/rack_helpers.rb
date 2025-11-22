require 'rack'

module RackHelpers
  def Rack.middleware_klass(&block)
    Class.new do
      define_method(:initialize) do |app, *opts, &block2|; @app = app; @opts = opts; @block = block2 || block end
      def call(env) = @block.call env, @app, @opts
    end
  end

  def Rack.define_middleware(name, &block)
    RackHelpers.const_set name, Rack.middleware_klass(&block)
  end

  Rack.define_middleware :Authentication do |env, app|
    token = env['HTTP_AUTHORIZATION'][/Bearer (.*)/, 1] rescue nil # Authorization: Bearer token
    token ||= env['HTTP_AUTH'][/Bearer (.*)/, 1] rescue nil # AUTH: Bearer token
    token ||= Rack::Request.new(env).cookies['token']
    token_h = JWT.decode token, '', false, algorithm: 'RS256' rescue nil
    token_h ||= [{}]

    if defined? OpenTelemetry::Trace
      OpenTelemetry::Trace.current_span.add_attributes'TOKEN' => token_h[0].to_json,
                                                      'username' => (token_h[0]['username'] || '')
    end
    Async::Task.current.define_singleton_method :token, &-> { token_h[0] }

    app.call env
  end

  # TODO:
  #  - Only required for cross-thread context transfer
  #
  # Rack.define_middleware :AsyncDBConnectionOT do |env, app|
  #   context_ = OpenTelemetry::Context.current
  #   OpenTelemetry::Context.with_current(context_) do
  #     OpenTelemetry::Trace.with_span(OpenTelemetry::Trace.current_span) do
  #       app.call env
  #     end
  #   end
  # end

  # Rack.define_middleware :SwaggerUI do |env, app, opts|
  #   # url = opts[:swagger]
  #   @static ||= Rack::Static.new app, urls: [''], root: "#{__dir__}/../swagger_ui/", index: 'index.html', cascade: true
  #   env['REQUEST_METHOD'] == 'GET' ? @static.call(env) : app.call(env)
  # end

  #

  Rack.define_middleware :OTELTraceFullRequest do |env, app, opts|
    request_headers = env.select { |k, _| k.start_with? 'HTTP_' }
    request_body = env['rack.input'].read

    response_code, response_headers, response_body = app.call(env)
    response_body = response_body.read if response_body.respond_to? :read
    otl_span( :Request, {request_headers: , request_body:, response_code:, response_headers: , response_body: }) {}
    [response_code, response_headers, response_body]
  end

  Rack.define_middleware :OTELTraceInfo do |env, app, opts|
    status, headers, body = app.call env
    if status.to_i >= 500
      otl_current_span{
        span_context = OpenTelemetry::Trace.current_span.context
        trace_id = span_context.trace_id.unpack1('H*')

        begin
          bj = JSON.parse(body.join)
          bj[:trace_id] = trace_id
          body = [bj.to_json]
        rescue =>e
          body = [body.join + "\ntrace_id: #{trace_id}"]
        end
      }
    end

    [status, headers, body]
  end

  Rack.define_middleware :NoCache do |env, app, opts|
    status, headers, body = app.call env
    headers['Cache-Control'] = 'private,max-age=0,must-revalidate,no-store'
    [status, headers, body]
  end

  # use RackHelpers::RequestsLimiter, limit: 1, path_regex: %r{^(?!.*healthcheck)}
  Rack.define_middleware :RequestsLimiter do |env, app, opts|
    @path_regex ||= opts[0][:path_regex] || %r{.*}
    @sem ||= Async::Semaphore.new(opts[0][:limit] || 5 )

    next app.call(env) unless env['PATH_INFO'] =~ @path_regex
    next [429, { 'Content-Type' => 'text/plain', 'Retry-After' => '1' }, ['Too Many Requests']] if @sem.blocking?

    @sem.acquire { app.call env }
  end

  # PATCH: for the Grape
  class Rack::Lint::Wrapper::InputWrapper
    def rewind = @input.rewind
  end if defined? Rack::Lint::Wrapper::InputWrapper

  class Rack::Lint
    def call(env = nil) = @app.call(env)
  end if defined? Rack::Lint

  class Rack::CommonLogger
    def log(env, status, header, began_at) = ()
  end
  # require 'rack/request'
  # # sinatra was resolved to 3.0.2, which depends on
  # #   rack (~> 2.2, >= 2.2.4)
  # # /home/user/.rbenv/versions/3.1.2/lib/ruby/gems/3.1.0/gems/rack-2.2.4/lib/rack/request.rb
  # module Rack::Request::Helpers
  #   alias old_post POST
  #   def POST = get_header(Rack::RACK_INPUT).empty? ? {} : old_post
  # end

  Rack.define_middleware :HeadersLogger do |env, app, opts|
    LOGGER.info env.select { %w'REQUEST_METHOD REQUEST_PATH REQUEST_URI QUERY_STRING'.include? _1 }
    LOGGER.info env.select { _1 =~ /HTTP/ }.transform_keys { _1.gsub 'HTTP_', '' }
    status, headers, body =app.call env

    if status.to_i / 100 == 5
      _body = body.to_s # each(&:to_s).join
      LOGGER.error [status, headers, _body]
      if defined? OpenTelemetry::Trace
        OpenTelemetry::Trace.current_span.tap do |span|
          event_attributes = { 'exception.type' => "HTTP #{status.to_i}", 'exception.message' => _body, 'exception.stacktrace' => '' }
          span.add_event('exception', attributes: event_attributes)
          span.status = OpenTelemetry::Trace::Status.error("Request error: #{status.to_i}")
        end
      end
    end

    LOGGER.info headers
    [status, headers, body]
  end

  Rack.define_middleware :RequestProfile do |env, app, opts|
    start = Time.now
    LOGGER.debug "start:#{start}"
    status, headers, body = app.call env
    LOGGER.debug "#{Time.now - start} sec - end (fiber id: #{Fiber.current.__id__}, async task: #{Async::Task.current})"
    headers['x-runtime'] = "#{Time.now - start}"
    # if headers['Content-Type'] =~ /html/
    #   headers['Set-Cookie'] = "Runtime=#{Time.now - start} sec;expires=Sat, 01-Jan-3000 00:00:00 GMT;path=/;"
    # end
    [status, headers, body]
  end

  class << self
    def rack_setup(app)
      # PATCH: for the Grape Swagger
      # https://github.com/ruby-grape/grape-swagger/pull/905
      # https://github.com/ruby-grape/grape-swagger/issues/904
      GrapeSwagger::DocMethods::ParseParams.instance_eval do
        def parse_enum_or_range_values(values)
          case values
          when Proc
            parse_enum_or_range_values(values.call) if values.parameters.empty?
          when Range
            parse_range_values(values) # if values.first.is_a?(Integer) TODO
          when Array
            { enum: values }
          else
            { enum: [values] } if values
          end
        end
      end if defined? GrapeSwagger::DocMethods::ParseParams

      app.use Rack.middleware_klass do |env, app|
        code, headers, body = app.call(env)
        if code == 404 && env['PATH_INFO'] == '/healthcheck'
          code, headers, body = [200, {'Content-Type' =>'application/json'}, [{ Status: 'Healthy' }.to_json ]]
        end
        [code, headers, body]
      end

      if defined? OpenTelemetry::Instrumentation::Rack::Instrumentation
        # use OpenTelemetry::Instrumentation::Rack::Middlewares::TracerMiddleware
        app.use *OpenTelemetry::Instrumentation::Rack::Instrumentation.instance.middleware_args
      end

      app.use Rack::Deflater
      app.use OTELTraceInfo if defined? OpenTelemetry::Trace

      unless defined?(PERFORMANCE) && PERFORMANCE
        app.use RequestProfile
        app.use HeadersLogger

        if defined? Rack::ODataCommonLogger
          app.use Rack::ODataCommonLogger, LOGGER # or use Rack::CommonLogger, LOGGER
        end
      end

      app.use Rack.middleware_klass do |env, app|
        code, headers, body = env['REQUEST_METHOD'] == 'OPTIONS' ? [204, {}, []] : app.call(env)

        # scheme = env['rack.url_scheme']
        # referer = URI.parse env['HTTP_REFERER']
        origin = env['HTTP_ORIGIN'] || '*'
        headers.merge!(
          # 'Access-Control-Allow-Origin' => "#{referer.scheme}://#{referer.host}",
          'Access-Control-Allow-Origin' => origin,
          'Vary' => 'Orign',
          'Access-Control-Allow-Methods' => 'GET, PUT, POST, PATCH, DELETE, HEAD, OPTIONS',
          'Access-Control-Allow-Headers' => '*',
          'Access-Control-Expose-Headers' => '*', # 'mcp-session-id'
          'Access-Control-Allow-Credentials' => 'true',
          'Access-Control-Max-Age' => '6000'
        )
        [code, headers, body]
      end

      # unless @run
      #   run ->(_env) { [200, {'Content-Type' => 'text/plain'}, ['OK!?']] }
      # end
    end
  end
end