require 'json'

class JsonRpcError < StandardError
  attr_reader :code

  def initialize(code:, message:)
    super(message)
    @code = code
  end
end

module RpcErrorHelpers
  def rpc_error!(code, message)
    raise ::JsonRpcError.new(code: code, message: message)
  end
end

class McpProcessor
  PROTOCOL_VERSION = '2025-06-18'
  DEFAULT_SERVER_INFO = {
    name: 'mcp-server',
    title: 'MCP Server',
    version: '1.0.0'
  }.freeze

  include RpcErrorHelpers
  ParseError = Class.new(StandardError) do
    attr_reader :body, :status

    def initialize(body:, status:)
      @body = body
      @status = status
      super("MCP parse error")
    end
  end

  def initialize(registry: nil, server_info: DEFAULT_SERVER_INFO, logger: (defined?(LOGGER) ? LOGGER : nil))
    @registry = registry
    @server_info = server_info
    @logger = logger
  end

  def root_endpoint
    root_response
  end

  def rpc_endpoint(raw_body)
    req = JSON.parse(raw_body.to_s)
    method = req["method"]
    params = req["params"]

    if req.key?("id")
      rpc_response(id: req["id"], method: method, params: params)
    else
      notification_response(method: method, params: params)
    end
  rescue JSON::ParserError => e
    @logger&.warn("MCP JSON parse failed: #{e.message}")
    body = error_response(id: nil, code: -32700, message: "Parse error")
    raise ParseError.new(body: body, status: 400)
  end

  def list_tools
    { tools: registry.list, nextCursor: 'no-more' }
  end

  def root_response
    json_rpc_response(id: nil) { list_tools }
  end

  def error_response(id:, code:, message:)
    json_rpc_response(id: id) { rpc_error!(code, message) }
  end

  def rpc_response(id:, method:, params:)
    json_rpc_response(id: id) { handle(method: method, params: params) }
  end

  def notification_response(method:, params:)
    handle_notification(method: method, params: params)
    nil
  rescue => e
    @logger&.error("Unhandled MCP notification error: #{e.class}: #{e.message}")
    nil
  end

  def handle(method:, params:)
    case method
    when "tools/list"  then list_tools
    # when "resources/list"  then {}
    # when "prompts/list"  then {}
    when "tools/call"  then call_tool(params || {})
    when "initialize"  then initialize_response
    when "notifications/initialized" then @logger&.debug(params); {}
    when "logging/setLevel" then @logger&.debug(params); {}
    else
      rpc_error!(-32601, "Unknown method #{method}")
    end
  end

  def handle_notification(method:, params:)
    case method
    when "notifications/initialized", "notifications/cancelled"
      @logger&.debug("MCP notification accepted: #{method}")
    else
      @logger&.debug("MCP notification ignored: #{method}")
    end
  end

  def initialize_(_body = nil)
    initialize_response
  end

  def initialize_response
    {
      serverInfo: @server_info,
      protocolVersion: PROTOCOL_VERSION,
      capabilities: {
        logging: {},
        prompts: { listChanged: false },
        resources: { listChanged: false },
        tools: { listChanged: false }
      }
    }
  end

  private

  def json_rpc_response(id:)
    body = { jsonrpc: "2.0", id: id }

    begin
      result = yield
      body[:result] = result unless body[:error] || result.nil?
    rescue JsonRpcError => e
      body[:error] = { code: e.code, message: e.message }
    rescue => e
      @logger&.error("Unhandled RPC error: #{e.class}: #{e.message}\n#{e.backtrace&.first}")
      body[:error] = { code: -32603, message: "Internal error" }
    end

    body.delete(:result) if body[:error]
    JSON.dump(body)
  end

  def call_tool(params)
    name      = params["name"]
    arguments = params["arguments"] || {}
    tool      = registry.fetch(name) || rpc_error!(-32601, "Unknown tool #{name}")
    response = tool.call_tool(arguments)
    return response if mcp_tool_response?(response)

    wrap_tool_response(response)
  end

  def registry
    @registry || ToolRegistry.default
  end

  def mcp_tool_response?(response)
    return false unless response.is_a?(Hash)

    [:content, :structuredContent, :isError, "content", "structuredContent", "isError"].any? do |key|
      response.key?(key)
    end
  end

  def wrap_tool_response(response)
    {
      content: [
        { "type": "text", "text": response.is_a?(String) ? response : JSON.dump(response) }
      ],
      isError: false
    }
  end
end
