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

    it 'lists tools via GET /' do
      get '/'
      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
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
      tool_result = response.dig('result', 'toolResult')
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
      post '/', '{invalid', headers
      expect(last_response.status).to eq(400)
      body = JSON.parse(last_response.body)
      expect(body.dig('error', 'code')).to eq(-32700)
    end

    def rpc_request(payload)
      post '/', JSON.dump(payload), headers
      expect(last_response.status).to eq(200)
      JSON.parse(last_response.body)
    end
  end
end
