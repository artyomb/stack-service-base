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

    it 'initializes the client session' do
      response = rpc_request(
        id: 10,
        method: 'initialize',
        params: {}
      )

      expect(response['id']).to eq(10)
      result = response['result']

      expect(result['serverInfo']).to include(
                                        'name' => 'mcp-server',
                                        'title' => 'MCP Server',
                                        'version' => '1.0.0'
                                      )

      expect(result['protocolVersion']).to eq(McpProcessor::PROTOCOL_VERSION)
      expect(result['capabilities']).to include(
                                          'logging' => {},
                                          'prompts' => { 'listChanged' => false },
                                          'resources' => { 'listChanged' => false },
                                          'tools' => { 'listChanged' => false }
                                        )
    end

    it 'lists tools via GET /mcp' do
      get '/mcp'
      expect(last_response.status).to eq(200)
      body = parsed_response_body
      expect(body['id']).to be_nil
      expect(body.dig('result', 'tools').map { |tool| tool['name'] }).to include('service_status', 'restart_service')
    end

    it 'lists tools via RPC' do
      body = rpc_request(id: 1, method: 'tools/list', params: {})
      expect(body['id']).to eq(1)
      names = body.dig('result', 'tools').map { |tool| tool['name'] }
      expect(names).to include('service_status', 'restart_service')
    end

    it 'executes service_status successfully' do
      response = rpc_request(
        id: 2,
        method: 'tools/call',
        params: { 'name' => 'service_status', 'arguments' => { 'service_name' => 'database-backend' } }
      )
      tool_results = response.dig('result', 'content')
      expect(tool_results[0]['type']).to eq('text')
      tool_result = JSON.parse tool_results[0]['text']
      expect(tool_result['service_name']).to eq('database-backend')
      expect(tool_result['status']).to eq('running')
    end

    it 'returns tool error when service is missing' do
      response = rpc_request(
        id: 3,
        method: 'tools/call',
        params: { 'name' => 'service_status', 'arguments' => { 'service_name' => 'ghost' } }
      )
      expect(response['result']).to be_nil
      expect(response.dig('error', 'code')).to eq(404)
      expect(response.dig('error', 'message')).to include('Unknown service ghost')
    end

    it 'returns error for unknown tools' do
      response = rpc_request(
        id: 4,
        method: 'tools/call',
        params: { 'name' => 'unknown', 'arguments' => {} }
      )
      expect(response.dig('error', 'code')).to eq(-32601)
    end

    it 'handles malformed JSON payloads' do
      post '/mcp', '{invalid', headers
      expect(last_response.status).to eq(400)
      body = parsed_response_body
      expect(body.dig('error', 'code')).to eq(-32700)
    end

    def rpc_request(payload)
      post '/mcp', JSON.dump(payload), headers
      expect(last_response.status).to eq(200)
      parsed_response_body
    end

    def parsed_response_body
      body = +''
      last_response.each { |chunk| body << chunk.to_s }
      data_lines = body.lines.select { |line| line.start_with?('data:') }
      payload_line = data_lines.reverse.find { |l| l !~ /ping/i } || data_lines.last
      payload = (payload_line || body).sub(/\Adata:\s*/, '').sub(/\n\z/, '')
      JSON.parse(payload)
    end
  end
end
