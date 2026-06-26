require_relative 'mcp_processor'
require_relative 'mcp_tool_registry'

MCP_PROCESSOR = McpProcessor.new

module McpHelper
  VALID_TRANSPORTS = [:sse, :json].freeze

  class << self
    def transport
      @transport ||= :sse
    end

    def transport=(value)
      value = value.to_sym
      raise ArgumentError, "Unknown MCP transport: #{value}" unless VALID_TRANSPORTS.include?(value)

      @transport = value
    end
  end

  def self.included(base)
    base.class_eval do

      error McpProcessor::ParseError do |err|
        status err.status
        err.body
      end

      get '/mcp' do
        content_type :json
        MCP_PROCESSOR.root_endpoint
      end

      post '/mcp' do
        request.body&.rewind

        response_body =
          begin
            MCP_PROCESSOR.rpc_endpoint(request.body.read.to_s)
          rescue McpProcessor::ParseError => e
            status e.status
            e.body
          end

        if response_body.nil?
          status 202
          headers 'Content-Length' => '0'
          ''
        elsif McpHelper.transport == :json
          content_type :json
          response_body
        else
          content_type 'text/event-stream'
          headers['Cache-Control'] = 'no-cache'
          headers['X-Accel-Buffering'] = 'no'
          headers['mcp-session-id'] = SecureRandom.uuid

          stream true do |s|
            s.callback { LOGGER.debug "stream closed: #{s}" }
            s << ['event: message', "data: #{response_body}", '', ''].join($/)
            s.close
          end
        end
      end
    end
  end
end
