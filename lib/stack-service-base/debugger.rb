unless ENV['RUBYOPT'] =~ /ruby-debug-ide/ # if defined?(::DEBUGGER__)

  ENV['RUBY_DEBUG_CHROME_PATH'] = ''
  ENV['RUBY_DEBUG_PORT'] = '12000'

  require 'debug/session'
  require 'debug/server'
  require 'debug/server_cdp'

  module DebugSkipMissingSources
    def get_source_code(path)
      super
    rescue Errno::ENOENT, Errno::ENOTDIR => e
      DEBUGGER__.warn "Skipped missing source for Chrome breakpoint: #{path} (#{e.message})"
      @src_map[path] ||= '' # keep DevTools happy even though the file is absent
    end
  end

  DEBUGGER__::UI_CDP.prepend(DebugSkipMissingSources)

  module FixedChromeUuid
    def chrome_setup
      @uuid = ENV['RUBY_DEBUG_CHROME_UUID'] || '12345678-1234-5678-9abc-def012345678'
      @chrome_pid = DEBUGGER__::UI_CDP.setup_chrome(@local_addr.inspect_sockaddr, @uuid)
      DEBUGGER__.warn <<~TXT
        With Chrome browser, type the following URL in the address-bar:
           devtools://devtools/bundled/inspector.html?v8only=true&panel=sources&noJavaScriptCompletion=true&ws=#{@local_addr.inspect_sockaddr}/#{@uuid}
      TXT
    end
  end

  DEBUGGER__::UI_TcpServer.prepend(FixedChromeUuid)


  module SkipMissingRegexBreakpoints
    def add_line_breakpoint(req, b_id, path)
      return super if File.exist?(path)

      DEBUGGER__.warn "Skipping breakpoint for missing source: #{path}"
      send_response req, breakpointId: b_id, locations: []
      # Returning keeps Chrome happy and avoids queuing the request
    end
  end

  DEBUGGER__::UI_CDP.prepend(SkipMissingRegexBreakpoints)

  module DebugKeepThreadsRunning
    def stop_all_threads
      DEBUGGER__.warn 'skip stop_all_threads (threads keep running)'
    end

    def restart_all_threads
      DEBUGGER__.warn 'skip restart_all_threads (threads already running)'
    end

    def wait_command_loop
      begin
        super
      rescue =>e
        DEBUGGER__.warn "EXCEPTION wait_command_loop: #{e.message}"
        retry
      end
    end
  end

  DEBUGGER__::Session.prepend(DebugKeepThreadsRunning)

  module FixedCdpUuid
    def send_chrome_response(req)
      env_uuid = ENV['RUBY_DEBUG_CHROME_UUID'] || '12345678-1234-5678-9abc-def012345678'
      @uuid = env_uuid if env_uuid # re-apply before every handshake
      DEBUGGER__.warn "Chrome UUID: #{env_uuid} (#{req.inspect})"
      super
    end
  end

  DEBUGGER__::UI_CDP.prepend(FixedCdpUuid)
  module DebugResetCdpCache
    def reset_cdp_script_cache!
      @scr_id_map = {}
      @obj_map = {}
    end
  end

  module DebugResetCdpOnHandshake
    def send_chrome_response(req)
      if req.match?(/^GET\s\/[\h]{8}-[\h]{4}-[\h]{4}-[\h]{4}-[\h]{12}\sHTTP\/1\.1/)
        if defined?(::DEBUGGER__::SESSION) && ::DEBUGGER__::SESSION.respond_to?(:reset_cdp_script_cache!)
          ::DEBUGGER__::SESSION.reset_cdp_script_cache!
        end
      end
      super
    end
  end

  DEBUGGER__::Session.prepend(DebugResetCdpCache)
  DEBUGGER__::UI_CDP.prepend(DebugResetCdpOnHandshake)

  module DebugPreloadSources
    class << self
      def register(*paths)
        stash.concat(paths.flatten.map { |p| File.expand_path(p) })
        stash.uniq!
      end

      def register_breakpoint(path, line, **opts)
        bp_entries << [File.expand_path(path), Integer(line), opts]
        p bp_entries
      end

      def each_source(&block) = stash.each(&block)
      def each_breakpoint(&block) = bp_entries.each(&block)

      private

      def stash = (@stash ||= [])
      def bp_entries = (@bp_entries ||= [])
    end
  end

  module DebugPreloadSession
    def announce_cdp_sources
      ensure_preloaded_breakpoints
      super if defined?(super)
    ensure
      push_cdp_sources_to_ui
    end

    private

    def ensure_preloaded_breakpoints
      @__preloaded_breakpoints ||= {}
      DebugPreloadSources.each_breakpoint do |path, line, opts|
        key = [path, line, opts]
        next if @__preloaded_breakpoints[key]

        begin
          ::DEBUGGER__.add_line_breakpoint(path, line, **opts)
          @__preloaded_breakpoints[key] = true
        rescue Errno::ENOENT => e
          DEBUGGER__.warn "Preload breakpoint skipped: #{path}:#{line} (#{e.message})"
        end
      end
    end

    def push_cdp_sources_to_ui
      return unless @ui&.respond_to?(:fire_event)

      DebugPreloadSources.each_source do |path|
        next if @scr_id_map[path]
        next unless File.file?(path)

        source   = File.read(path)
        script_id = (@scr_id_map.size + 1).to_s
        @scr_id_map[path] = script_id
        @src_map[script_id] = source

        @ui.fire_event 'Debugger.scriptParsed',
                       scriptId: script_id,
                       url: path,
                       startLine: 0,
                       startColumn: 0,
                       endLine: source.lines.count,
                       endColumn: 0,
                       executionContextId: 1,
                       hash: source.hash.inspect
      end
    end
  end

  module DebugPreloadHandshake
    def send_chrome_response(request)
      res = super
      if request.match?(/^GET\s\/[\h]{8}-[\h]{4}-[\h]{4}-[\h]{4}-[\h]{12}\sHTTP\/1\.1/) &&
         defined?(::DEBUGGER__::SESSION)
        ::DEBUGGER__::SESSION.extend(DebugPreloadSession)
        ::DEBUGGER__::SESSION.announce_cdp_sources
      end
      res
    end
  end

  DEBUGGER__::UI_CDP.prepend(DebugPreloadHandshake)
  # DEBUGGER__::Session.prepend(DebugPreloadSession)
  # DEBUGGER__::UI_CDP.prepend(DebugPreloadHandshake)

  DebugPreloadSources.register(
    Dir[File.expand_path('../**/*')]
  )

  break_line_index = File.readlines(__FILE__).index{ _1. match?(/remote [d]ebugger default breakpoint/) }.to_i + 2
  DEBUGGER__.warn "break_line_index: #{break_line_index}"

  DebugPreloadSources.register_breakpoint File.expand_path(__FILE__), break_line_index

  Thread.new do
    DEBUGGER__.open open: 'chrome', nonstop: true

    loop do
      # remote debugger default breakpoint
      sleep 1
    end
  end


  unless ENV['RUBYOPT'] =~ /ruby-debug-ide/
    # ENV['RUBY_DEBUG_PORT'] = '12345' #/run/user/1000/rdbg-54391
    # require 'debug/open_nonstop'
    # to connect
    # rdbg -A
    # rdbg --attach 12345
    # Chrome Devtools https://github.com/ruby/debug/pull/334/files#diff-5fc3d0a901379a95bc111b86cf0090b03f857edfd0b99a0c1537e26735698453R55-R64
    # rdbg target.rb -O chrome --port 1234
  end


end
