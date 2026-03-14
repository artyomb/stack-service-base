# SafeExec provides two related safety wrappers for Unix-like systems:
# 1. Run a Ruby block in an isolated fork with a hard timeout.
# 2. Run an external command with captured output, streaming callbacks,
#    process-group cleanup, and optional raising "bang" variants.
#
# Design notes:
# - Timeouts are enforced with a monotonic clock.
# - Child work is placed into its own process group so timeout handling can
#   terminate the whole subtree, not just the direct child.
# - `call`/`call_result` return values must be Marshal-serializable because
#   data is sent from the child process to the parent over a pipe.
# - `capture` yields streamed output as `|stream, chunk|`, where `stream` is
#   `:stdout` or `:stderr`.
module SafeExec
  TERM_GRACE_SECONDS = 5

  # Result of block execution via `call_result`.
  #
  # Fields:
  # - ok: true when the child block completed without raising
  # - result: block return value, if execution succeeded
  # - exception: reconstructed exception object, if any
  # - timed_out: true when the child exceeded the deadline
  StepResult = Struct.new(:ok, :result, :exception, :timed_out, keyword_init: true) do
    def success? = ok && !timed_out && exception.nil?
    def timed_out? = !!timed_out
  end

  # Result of external command execution via `capture`.
  #
  # Fields:
  # - stdout: collected standard output
  # - stderr: collected standard error
  # - status: Process::Status for completed commands
  # - timed_out: true when the process group was terminated on deadline
  # - exception: wrapper-level error, typically spawn/setup failure
  CommandResult = Struct.new(:stdout, :stderr, :status, :timed_out, :exception, keyword_init: true) do
    def success? = !timed_out && exception.nil? && status&.success?
    def timed_out? = !!timed_out
    def exitstatus = status&.exitstatus
    def out = stdout
    def err = stderr
  end

  class Error < StandardError
    attr_reader :result

    def initialize(message = nil, result: nil)
      super(message)
      @result = result
    end
  end

  class TimeoutError < Error; end
  class SpawnError < Error; end
  class ExitError < Error; end
  class SerializationError < Error; end

  module_function

  def ensure_open3_loaded
    return if defined?(Open3)

    require 'open3'
  end
  private_class_method :ensure_open3_loaded if respond_to?(:private_class_method)

  def ensure_timeout_loaded
    return if defined?(Timeout::Error)

    require 'timeout'
  end
  private_class_method :ensure_timeout_loaded if respond_to?(:private_class_method)

  # Execute a Ruby block in a forked subprocess.
  #
  # Returns the block result on success.
  # Raises the reconstructed child exception or TimeoutError on failure.
  def call(timeout:, &block)
    ensure_timeout_loaded
    result = call_result(timeout:, &block)
    raise result.exception if result.exception

    result.result
  end

  # Bang alias for `call`.
  def call!(timeout:, &block) = call(timeout:, &block)

  # Execute a Ruby block in a forked subprocess and return a structured result.
  #
  # This is the non-raising API for isolated block execution.
  # The block return value must be Marshal-serializable.
  def call_result(timeout:, &block)
    ensure_timeout_loaded
    reader, writer = IO.pipe
    pid = fork do
      reader.close
      Process.setpgrp

      result = block.call
      dump_payload(writer, step_payload(result:))
    rescue => e
      dump_payload(writer, step_payload(exception: e))
    ensure
      writer.close unless writer.closed?
      exit! 0
    end

    writer.close
    timed_out = wait_or_terminate(pid, timeout)
    if timed_out
      return StepResult.new(
        ok: false,
        timed_out: true,
        exception: TimeoutError.new("Timed out after #{timeout}s")
      )
    end

    payload = Marshal.load(reader)
    StepResult.new(
      ok: payload[:ok],
      result: payload[:result],
      exception: build_exception(payload),
      timed_out: false
    )
  rescue EOFError => e
    StepResult.new(ok: false, exception: e, timed_out: false)
  ensure
    reader.close if reader && !reader.closed?
  end

  # Run an external command with timeout control and full output capture.
  #
  # When a block is given, chunks are yielded as they arrive:
  #   capture("bash", "-lc", "echo hi; echo warn >&2") { |stream, chunk| ... }
  #
  # Yields:
  # - stream: :stdout or :stderr
  # - chunk: String
  #
  # Returns CommandResult and does not raise for non-zero exit status.
  def capture(*cmd, timeout:, &block)
    ensure_open3_loaded
    stdout = +''
    stderr = +''
    status = nil

    Open3.popen3(*cmd, pgroup: true) do |stdin, child_stdout, child_stderr, wait_thr|
      stdin.close
      pid = wait_thr.pid
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

      until wait_thr.join(0)
        drain_pair(child_stdout, stdout, :stdout, &block)
        drain_pair(child_stderr, stderr, :stderr, &block)

        if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
          terminate_process_group(pid)
          drain_all(child_stdout, stdout, :stdout, &block)
          drain_all(child_stderr, stderr, :stderr, &block)
          return CommandResult.new(stdout:, stderr:, timed_out: true)
        end

        IO.select([child_stdout, child_stderr], nil, nil, 0.1)
      end

      drain_all(child_stdout, stdout, :stdout, &block)
      drain_all(child_stderr, stderr, :stderr, &block)
      status = wait_thr.value
    end

    CommandResult.new(stdout:, stderr:, status:, timed_out: false)
  rescue => e
    CommandResult.new(stdout:, stderr:, exception: SpawnError.new(e.message, result: nil), timed_out: false)
  end

  # Raising variant of `capture`.
  #
  # Raises:
  # - TimeoutError on timeout
  # - SpawnError on wrapper-level execution/setup failure
  # - ExitError on non-zero exit status
  #
  # Returns CommandResult on success.
  def capture!(*cmd, timeout:, &block)
    ensure_timeout_loaded
    result = capture(*cmd, timeout:, &block)
    raise TimeoutError.new("Timed out after #{timeout}s", result:) if result.timed_out?
    raise result.exception if result.exception
    raise ExitError.new(exit_error_message(cmd, result), result:) unless result.status&.success?

    result
  end

  def run(*cmd, timeout:, &block) = capture(*cmd, timeout:, &block)
  def run!(*cmd, timeout:, &block) = capture!(*cmd, timeout:, &block)

  # Marshal the child payload back to the parent process.
  # If the block result cannot be serialized, convert it into a structured error
  # so the parent still receives a useful failure.
  def dump_payload(writer, payload)
    Marshal.dump(payload, writer)
  rescue TypeError => e
    serializable = step_payload(
      exception: SerializationError.new("Result is not serializable: #{e.message}")
    )
    Marshal.dump(serializable, writer) rescue nil
  end
  private_class_method :dump_payload if respond_to?(:private_class_method)

  def step_payload(result: nil, exception: nil)
    {
      ok: exception.nil?,
      result: result,
      exception_class: exception&.class&.name,
      exception_message: exception&.message,
      exception_backtrace: exception&.backtrace
    }
  end
  private_class_method :step_payload if respond_to?(:private_class_method)

  # Rebuild a best-effort exception object in the parent process from a payload
  # received over Marshal.
  def build_exception(payload)
    return nil unless payload[:exception_message]

    klass_name = payload[:exception_class].to_s
    klass = klass_name.empty? ? RuntimeError : Object.const_get(klass_name)
    exception = klass.new(payload[:exception_message])
    exception.set_backtrace(Array(payload[:exception_backtrace])) if exception.respond_to?(:set_backtrace)
    exception
  rescue NameError
    exception = RuntimeError.new(payload[:exception_message])
    exception.set_backtrace(Array(payload[:exception_backtrace])) if exception.respond_to?(:set_backtrace)
    exception
  end
  private_class_method :build_exception if respond_to?(:private_class_method)

  # Drain as much currently available data as possible from one pipe without
  # blocking, append it to the target buffer, and optionally stream it to the
  # caller-supplied block.
  def drain_pair(io, buffer, stream)
    loop do
      chunk = io.read_nonblock(4096, exception: false)
      case chunk
      when String
        buffer << chunk
        yield stream, chunk if block_given?
      when :wait_readable, nil
        return
      end
    end
  rescue IOError, Errno::EIO
    nil
  end
  private_class_method :drain_pair if respond_to?(:private_class_method)

  # Drain the remainder of a finished stream and optionally yield it.
  def drain_all(io, buffer, stream)
    chunk = io.read
    return unless chunk

    buffer << chunk
    yield stream, chunk if block_given?
  rescue IOError, Errno::EIO
    nil
  end
  private_class_method :drain_all if respond_to?(:private_class_method)

  # Wait for a child process until the deadline, then terminate the whole
  # process group if it is still running.
  def wait_or_terminate(pid, timeout)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

    loop do
      waited_pid, = Process.waitpid2(pid, Process::WNOHANG)
      return false if waited_pid
      break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      sleep 0.2
    end

    terminate_process_group(pid)
    true
  end
  private_class_method :wait_or_terminate if respond_to?(:private_class_method)

  # Graceful shutdown policy:
  # - send TERM to the child process group
  # - wait up to TERM_GRACE_SECONDS
  # - send KILL if anything is still alive
  def terminate_process_group(pid)
    Process.kill('TERM', -pid)
  rescue Errno::ESRCH
    return
  ensure
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + TERM_GRACE_SECONDS
    loop do
      waited_pid, = Process.waitpid2(pid, Process::WNOHANG)
      return if waited_pid
      break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      sleep 0.2
    end

    begin
      Process.kill('KILL', -pid)
    rescue Errno::ESRCH
      nil
    end

    begin
      Process.waitpid(pid)
    rescue Errno::ECHILD
      nil
    end
  end
  private_class_method :terminate_process_group if respond_to?(:private_class_method)

  # Build an informative error message for `capture!` failures.
  def exit_error_message(cmd, result)
    parts = []
    parts << "Command failed: #{cmd.join(' ')}"
    parts << "exit status #{result.exitstatus}" if result.exitstatus
    parts.join(' with ')
  end
  private_class_method :exit_error_message if respond_to?(:private_class_method)
end

if $PROGRAM_NAME == __FILE__
  puts '[self-test] capture with streaming'
  result = SafeExec.capture('bash', '-lc', 'echo out; echo err >&2', timeout: 2) do |stream, chunk|
    puts "  #{stream}: #{chunk.inspect}"
  end
  puts "  success?: #{result.success?}"
  puts "  stdout: #{result.stdout.inspect}"
  puts "  stderr: #{result.stderr.inspect}"

  puts '[self-test] capture! exit error'
  begin
    SafeExec.capture!('bash', '-lc', 'echo boom >&2; exit 7', timeout: 2)
  rescue SafeExec::ExitError => e
    puts "  exit_error: #{e.message}"
    puts "  stderr: #{e.result.stderr.inspect}"
  end

  puts '[self-test] call data result'
  data = SafeExec.call(timeout: 2) { { ok: true, items: [1, 2, 3] } }
  puts "  data: #{data.inspect}"

  puts '[self-test] call timeout'
  begin
    SafeExec.call(timeout: 1) do
      sleep 2
      true
    end
  rescue SafeExec::TimeoutError, Timeout::Error => e
    puts "  timeout: #{e.class}: #{e.message}"
  end
end
