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

  include RpcErrorHelpers
  ParseError = Class.new(StandardError) do
    attr_reader :body, :status

    def initialize(body:, status:)
      @body = body
      @status = status
      super("MCP parse error")
    end
  end

  def initialize(logger: LOGGER)
    @logger = logger
  end

  def root_endpoint
    root_response
  end

  def rpc_endpoint(raw_body)
    req = JSON.parse(raw_body.to_s)
    rpc_response(id: req["id"], method: req["method"], params: req["params"])
  rescue JSON::ParserError
    body = error_response(id: nil, code: -32700, message: "Parse error")
    raise ParseError.new(body: body, status: 400)
  end

  def list_tools
    { tools: ToolRegistry.list, nextCursor: 'no-more' }
  end

  def root_response
    json_rpc_response(id: nil) { list_tools }
  end

  def error_response(id:, code:, message:)
    json_rpc_response(id: id) { rpc_error!(code, message) }
  end

  def rpc_response(id:, method:, params:)
    json_rpc_response(id: id) { |body| handle(method: method, params: params, body: body) }
  end

  def handle(method:, params:, body: )
    case method
    when "tools/list"  then list_tools
    # when "resources/list"  then {}
    # when "prompts/list"  then {}
    when "tools/call"  then call_tool(params || {})
    when "initialize"  then initialize_(body)
    when "notifications/initialized" then LOGGER.debug params; {}
    when "logging/setLevel" then LOGGER.debug params; {}
    else
      rpc_error!(-32601, "Unknown method #{method}")
    end
  end

  # https://gist.github.com/ruvnet/7b6843c457822cbcf42fc4aa635eadbb

  def initialize_(body)
    {
      serverInfo: {
        name: 'mcp-server',
        title: 'MCP Server',
        version: '1.0.0'
      },
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
      result = yield(body)
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
    tool      = ToolRegistry.fetch(name) || rpc_error!(-32601, "Unknown tool #{name}")
    response = tool.call(arguments)
    {
      content: [
        { "type": "text", "text": response.is_a?(String) ? response : response.to_json }
      ],
      isError: false
    }
  end
end
