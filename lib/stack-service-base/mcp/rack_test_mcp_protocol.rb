require 'json'

module Rack
  module Test
    module McpProtocol
      def rpc_request(payload)
        post '/mcp', JSON.dump(payload), { 'CONTENT_TYPE' => 'application/json' }
        expect(last_response.status).to eq(200)
        parsed_response_body
      end

      def parsed_response_body
        body = +''
        last_response.each { |chunk| body << chunk.to_s }
        data_lines = body.lines.select { |line| line.start_with?('data:') }
        payload_line = data_lines.reverse.find { |l| l !~ /ping/i } || data_lines.last
        payload = (payload_line || body).sub(/\Adata:\s*/, '').sub(/\n\z/, '')
        JSON.parse(payload, symbolize_names: true)
      end

      def mcp_list_tools
        req_id = next_id
        response = rpc_request(id: req_id, method: 'tools/list', params: {})
        expect(response[:id]).to eq(req_id)
        response.dig(:result, :tools)
      end

      def mcp_call_tool(name:, arguments:)
        response = mcp_call_tool_raw(name: name, arguments: arguments)
        tool_results = response.dig(:result, :content)
        expect(tool_results[0][:type]).to eq('text')
        JSON.parse(tool_results[0][:text], symbolize_names: true)
      end

      def mcp_call_tool_raw(name:, arguments:)
        rpc_request(
          id: next_id,
          method: 'tools/call',
          params: { 'name' => name, 'arguments' => arguments }
        )
      end

      private

      def next_id
        @next_id ||= -1
        @next_id += 1
      end
    end
  end
end

