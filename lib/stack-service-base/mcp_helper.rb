require_relative 'mcp_processor'
require_relative 'mcp_tool_registry'

MCP_PROCESSOR = McpProcessor.new

module McpHelper
  def self.included(base)
    base.class_eval do

      error McpProcessor::ParseError do |err|
        status err.status
        err.body
      end

      get  '/mcp' do
        content_type :json
        MCP_PROCESSOR.root_endpoint
      end

      post '/mcp' do
        content_type 'text/event-stream'
        headers['Cache-Control'] = 'no-cache'
        headers['X-Accel-Buffering'] = 'no'
        headers['mcp-session-id'] = SecureRandom.uuid
        request.body&.rewind
        body = request.body.read.to_s

        response_body =
          begin
            MCP_PROCESSOR.rpc_endpoint(body)
          rescue McpProcessor::ParseError => e
            status e.status
            e.body
          end

        LOGGER.debug "request body: #{body}"
        LOGGER.debug "response body: #{response_body}"

        stream true do |s|
          s.callback { LOGGER.debug "stream closed: #{s}" }
          s << "event: message\ndata: #{response_body}\n\n"
          s.close
        end
      end
    end
  end
end
