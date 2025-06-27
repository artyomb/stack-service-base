require 'sequel'
require 'async/semaphore'
# $stdout.sync = true

$local_log = -> msg do
  otl_current_span{ |span|
    span.add_event("FiberPool", attributes: {
      F: Fiber.current.__id__, T: Thread.current.__id__, A: self.__id__,
      message: msg
    }.transform_keys(&:to_s) )
  }

  return if defined? PERFORMANCE
  $stdout.puts "F:#{Fiber.current.__id__} : T:#{Thread.current.__id__} : A:#{self.__id__} : #{msg}"
  # LOGGER.debug :fiber_pool, msg
end



class FiberConnectionPool < Sequel::ConnectionPool
  VALIDATION_TIMEOUT = 20
  POOL_SIZE = 10

  def initialize(db, opts = OPTS)
    otl_span "FiberConnectionPool.initialize" do |span|
      super
      @allocator = ->() {
        make_new(:default).tap { |conn|
          $local_log["new connection (fiber pool) #{conn.__id__}"]
        }
      }
      @stock = []
      @acquired = {}
      @sp = Async::Semaphore.new opts[:max_connections] || POOL_SIZE
    end
  end

  def is_valid_connection?(conn)
    sql = valid_connection_sql
    log_connection_execute(conn, sql)
    true
  rescue =>e_
    conn.close rescue nil
    false
  end

  def hold(_server = nil)
    return yield @acquired[Fiber.current] if @acquired[Fiber.current] # protect from recursion
    $local_log["hold in (fiber pool: #{__id__}) #{@stock.map{_1.__id__}}"]
    fiber = Fiber.current
    try_count = 2

    @sp.acquire do
      until @acquired[fiber] &&
        ( @acquired[fiber].instance_eval { @last_use_.nil? || (Time.now - @last_use_).to_i < VALIDATION_TIMEOUT } ||
          is_valid_connection?(@acquired[fiber]) )

        @acquired[fiber] = @stock.shift || @allocator.call
      end

      @acquired[fiber].instance_eval { @last_use_ = Time.now }
      yield @acquired[fiber]

    rescue Sequel::DatabaseDisconnectError => e
      $local_log["remove connection (fiber pool) retry(#{try_count})"]
      @acquired.delete(fiber)
      (try_count -=1) < 0 ? raise : retry

    rescue =>e
      $stdout.puts e.message
      $stdout.puts e.backtrace[0..10].join "\n"
      $local_log['remove connection (fiber pool) give up']
      @acquired.delete(fiber)
      raise
    ensure
      @stock.push @acquired.delete(fiber) if @acquired[fiber]
      $local_log["hold out (fiber pool: #{__id__}) #{@stock.map{_1.__id__}}"]
    end
  end

  def size = @acquired.size
  def max_size = @sp.limit
  # def preconnect(_concurrent = false) = :unimplemented
  def disconnect(symbol)
    until @stock.empty?
      $local_log['disconnect connection (fiber pool)']
      @stock.shift.close
    end
  end
  # def servers = []
  def pool_type = :fiber # :threaded
  def sync = yield
end

# Override Sequel::Database to use FiberConnectionPool by default.
Sequel::Database.prepend(Module.new do
  def connection_pool_default_options = { pool_class: FiberConnectionPool }
end)

require 'sequel/adapters/postgres'

class Sequel::Postgres::Adapter
  def execute_query(sql, args)
    $stdout.puts "F:#{Fiber.current.__id__} : T:#{Thread.current.__id__} : A:#{self.__id__} : #{sql[0..60]}" unless defined? PERFORMANCE
    $local_log["query (#{self.__id__}): #{sql.slice(0, 60)}"]
    @db.log_connection_yield(sql, self, args) do
      args ? async_exec_params(sql, args) : async_exec(sql)
    end
  rescue => e
    $local_log["Error: #{e.message}"]
    $stdout.puts e.message
    raise
  end
end