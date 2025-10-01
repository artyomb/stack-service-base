require 'console'
require 'fiber'

QUIET = ENV.fetch('QUIET', 'false') == 'true'
PERFORMANCE = ENV.fetch('PERFORMANCE', 'false') == 'true'

ENV['CONSOLE_LEVEL'] ||= 'all' unless QUIET || PERFORMANCE
# ENV['CONSOLE_OUTPUT'] ||= 'XTerm' # JSON,Text,XTerm,Default

CONSOLE_LOGGER = Class.new {
  def <<(...) = Console.logger.info(...)
  def info(...) = Console.logger.info(...)
  def debug(...) = Console.logger.debug(...)
  def debug1(...) = Console.logger.debug(...)
  def debug2(...) = Console.logger.debug(...)
  def debug3(...) = Console.logger.debug(...)
  def warn(...) = Console.logger.warn(...)
  def error(...) = Console.logger.error(...)
  def fatal(...) = Console.logger.fatal(...)
  def exception(e)
    backtrace = e.backtrace.join "\n" rescue ''
    Console.logger.fatal(e.message, backtrace)
  end
}.new

if QUIET
  ENV['CONSOLE_LEVEL'] = 'error'
  LOGGER = CONSOLE_LOGGER

  # LOGGER = Class.new {
  #   def <<(...) = nil
  #   def info(...) = nil
  #   def debug(...) = nil
  #   def debug1(...) = nil
  #   def debug2(...) = nil
  #   def debug3(...) = nil
  #   def warn(...) = nil
  #   def error(...) = nil
  #   def fatal(...) = nil
  # }.new
else
  $stdout.sync = true
  $stderr.sync = true
  # class Fiber
  #   alias_method :old_init, :initialize
  #   attr_reader :parent
  #
  #   def initialize(&)
  #     @parent = Fiber.current
  #     old_init(&)
  #   end
  #
  #   def parents
  #     list = [@parent]
  #     list << list.last.parent while list.last.respond_to?(:parent) && !list.last.parent.nil?
  #     list
  #   end
  # end

  # https://socketry.github.io/traces/guides/getting-started/index.html
  # OpenTelemetry / Datadog
  # https://socketry.github.io/console/guides/getting-started/index.html
  # ENV['TRACES_BACKEND'] = 'traces/backend/console'
  # ENV['CONSOLE_LEVEL'] = 'all'
  # ENV['CONSOLE_OUTPUT'] = 'XTerm' # JSON,Text,XTerm,Default
  # TRACE_METHODS = true
  TRACE_METHODS ||= !PERFORMANCE unless defined? TRACE_METHODS
  if TRACE_METHODS
    trace = TracePoint.new(:call, :return, :b_call, :b_return) { |tp| # :thread_begin, :thread_end
      call_stack = Thread.current[:call_stack] ||= {}
      call_stack_fiber = call_stack[Fiber.current.__id__] ||= []
      call_stack_fiber << [tp.defined_class, tp.method_id] if [:call, :b_call].include? tp.event
      call_stack_fiber.pop if [:return, :b_return].include? tp.event
    }
    trace.enable
  end
  # the_method
  # trace.disable
  LOG_DEPTH ||= 10 unless defined? LOG_DEPTH
  LOGGER = Class.new {
    def initialize = @context_list ||= {}

    def add_context(name)
      task = Async::Task.current?
      @context_list[task.__id__] = name
    end

    def find_context
      return '' unless Thread.current[:async_task]

      t_stack = [Async::Task.current]
      t_stack << t_stack.last.parent while t_stack.last.parent
      task = t_stack.find { @context_list[_1.__id__] }

      task ? " [#{@context_list[task.__id__]}] " : ''
    end

    def <<(...) = do_log(:info, ...)

    def info(...) = do_log(:info, ...)

    def debug(...) = do_log(:debug, ...)

    def debug1(...) = do_log(:debug1, ...)

    def debug2(...) = do_log(:debug2, ...)

    def debug3(...) = do_log(:debug3, ...)

    def warn(...) = do_log(:warn, ...)

    def error(...) = do_log(:error, ...)

    def fatal(...) = do_log(:fatal, ...)

    def exception(e)
      backtrace = e.backtrace.join "\n" rescue ''
      do_log(:fatal, e.message, backtrace)
    end

    def do_log(name, prefix_, *args)
      prefix = prefix_.class == String ? prefix_ : prefix_.inspect

      debug_level = name[/(\d+)/, 1].to_i
      unless debug_level > LOG_DEPTH
        if TRACE_METHODS
          call_stack = Thread.current[:call_stack] ||= {}
          call_stack_fiber = call_stack[Fiber.current.__id__] ||= []
          last = call_stack_fiber[-3] ? call_stack_fiber[-3].join('.').gsub('Class:', '').gsub(/[#<>]/, '') : ''
          last += find_context
          msg = "\e[33m#{last}:\e[0m \e[38;5;254m#{prefix}"
        else
          msg = "#{prefix}"
        end
        _name = name.to_s.gsub(/\d/, '')
        _name = 'info' if _name == '<<'
        Console.logger.send _name.to_s.gsub(/\d/, ''), msg, *args
      end
    end
  }.new

end

LOGGER_GRAPE = Class.new {
  def method_missing(name, d)
    Console.logger.send  name, "REST_API: #{d[:method]} #{d[:path]} #{d[:params]} - #{d[:status]} host:#{d[:host]} time:#{d[:time]}"
  end
}.new

$stdout.puts "QUIET: #{QUIET}"
$stdout.puts "PERFORMANCE: #{PERFORMANCE}"

ENV.select{ |k,v| k =~ /CONSOLE_/}.each { |k,v| $stdout.puts "#{k}: #{v}"}
