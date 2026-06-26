require 'json'

RSpec.describe 'Integration Tests' do
  describe 'Service basics' do
    it 'responds to healthcheck' do
      get '/healthcheck'
      expect(last_response.status).to eq(200)
    end
  end

  describe 'Tool registry' do
    let(:headers) { { 'CONTENT_TYPE' => 'application/json' } }

    after do
      McpHelper.transport = :sse
    end

    it 'initializes the client session' do
      req_id = next_id
      response = rpc_request(
        id: req_id,
        method: 'initialize',
        params: {}
      )

      expect(response[:id]).to eq(req_id)
      result = response[:result]

      expect(result[:serverInfo]).to include(
        name: 'mcp-server',
        title: 'MCP Server',
        version: '1.0.0'
      )

      expect(result[:protocolVersion]).to eq(McpProcessor::PROTOCOL_VERSION)
      expect(result[:capabilities]).to include(
        logging: {},
        prompts: { listChanged: false },
        resources: { listChanged: false },
        tools: { listChanged: false }
      )
    end

    it 'lists tools via GET /mcp' do
      get '/mcp'
      expect(last_response.status).to eq(200)
      body = parsed_response_body
      expect(body[:id]).to be_nil
      expect(body.dig(:result, :tools).map { |tool| tool[:name] }).to include('service_status', 'restart_service')
    end

    it 'lists tools via RPC' do
      names = mcp_list_tools.map { |tool| tool[:name] }
      expect(names).to include('service_status', 'restart_service')
    end

    it 'keeps SSE as the default POST transport' do
      rpc_request(id: next_id, method: 'tools/list', params: {})
      expect(last_response.content_type).to include('text/event-stream')
    end

    it 'returns plain JSON when JSON transport is selected' do
      McpHelper.transport = :json

      response = rpc_request(id: next_id, method: 'tools/list', params: {})

      expect(last_response.content_type).to include('application/json')
      expect(response.dig(:result, :tools).map { |tool| tool[:name] }).to include('service_status')
    end

    it 'returns an empty 202 response for notifications' do
      post '/mcp', JSON.dump(method: 'notifications/initialized', params: {}), headers

      expect(last_response.status).to eq(202)
      expect(last_response.body).to eq('')
    end

    it 'supports direct input schemas and annotations' do
      tool = mcp_list_tools.find { |item| item[:name] == 'schema_echo' }

      expect(tool[:inputSchema]).to include(
        type: 'object',
        required: ['value']
      )
      expect(tool.dig(:inputSchema, :properties, :value)).to include(
        type: 'string',
        description: 'Value to echo'
      )
      expect(tool[:annotations]).to include(readOnlyHint: true)
    end

    it 'executes service_status successfully' do
      tool_result = mcp_call_tool(name: 'service_status', arguments: { service_name: 'database-backend' })
      expect(tool_result[:service_name]).to eq('database-backend')
      expect(tool_result[:status]).to eq('running')
    end

    it 'passes complete MCP tool responses through' do
      response = mcp_call_tool_raw(name: 'full_response_echo', arguments: { value: 'ok' })

      expect(response.dig(:result, :content, 0, :text)).to eq('ok')
      expect(response.dig(:result, :structuredContent, :value)).to eq('ok')
      expect(response.dig(:result, :isError)).to be(false)
    end

    it 'supports custom instance registries for processors' do
      registry = ToolRegistry::Registry.new
      registry.define(:custom_echo) do
        description 'Echo a value from a custom registry'
        input value: { type: 'string', required: true }
        call { |inputs| { value: inputs[:value] } }
      end

      processor = McpProcessor.new(
        registry: registry,
        server_info: { name: 'custom-server', title: 'Custom Server', version: '2.0.0' },
        logger: nil
      )
      response = JSON.parse(
        processor.rpc_endpoint(JSON.dump(id: 100, method: 'tools/list', params: {})),
        symbolize_names: true
      )

      expect(response.dig(:result, :tools).map { |tool| tool[:name] }).to eq(['custom_echo'])

      init_response = JSON.parse(
        processor.rpc_endpoint(JSON.dump(id: 101, method: 'initialize', params: {})),
        symbolize_names: true
      )
      expect(init_response.dig(:result, :serverInfo)).to include(
        name: 'custom-server',
        title: 'Custom Server',
        version: '2.0.0'
      )
    end

    it 'returns tool error when service is missing' do
      response = mcp_call_tool_raw(name: 'service_status', arguments: { service_name: 'ghost' })
      expect(response[:result]).to be_nil
      expect(response.dig(:error, :code)).to eq(-32000)
      expect(response.dig(:error, :message)).to include('Unknown service ghost')
    end

    it 'returns error for unknown tools' do
      response = mcp_call_tool_raw(name: 'unknown', arguments: {})
      expect(response.dig(:error, :code)).to eq(-32601)
    end

    it 'handles malformed JSON payloads' do
      post '/mcp', '{invalid', headers
      expect(last_response.status).to eq(400)
      body = parsed_response_body
      expect(body.dig(:error, :code)).to eq(-32700)
    end
  end
end
