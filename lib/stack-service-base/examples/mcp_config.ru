require 'sinatra'
require 'stack-service-base'

StackServiceBase.rack_setup self

SERVICES = {
  "database-backend" => {
    status: "running",
    uptime: 72 * 3600,                       # seconds
    last_restart: Time.now - 72 * 3600
  }
}

require 'stack-service-base/mcp_processor'
require 'stack-service-base/mcp_tool_registry'

MCP_PROCESSOR = McpProcessor.new

Tool :service_status do
  description 'Check current status of a service'
  input service_name: { type: "string", description: "Service name to inspect", required: true }
  execute do |inputs|
    service_name = inputs[:service_name]
    service = SERVICES[service_name]
    rpc_error!(404, "Unknown service #{service_name}") unless service
    {
      toolResult: {
        service_name: service_name,
        status: service[:status],
        uptime_sec: service[:uptime],
        last_restart: service[:last_restart].utc.iso8601,
      }
    }
  end
end

Tool :restart_service do
  description 'Restart a service'
  input service_name: { type: "string", description: "Service name to restart", required: true },
        force: { type: "boolean", default: false, description: "Force restart if graceful fails" }
  execute do |inputs|
    service_name = inputs[:service_name]
    service = SERVICES[service_name]
    rpc_error!(404, "Unknown service #{service_name}") unless service

    service[:status]       = "running"
    service[:last_restart] = Time.now
    service[:uptime]       = 0

    {
      toolResult: {
        service_name: service_name,
        status: service[:status],
        restarted_at: service[:last_restart].utc.iso8601,
        force: inputs.fetch(:force, false)
      }
    }
  end
end

before { content_type :json }
error McpProcessor::ParseError do |err|
  status err.status
  err.body
end

get  '/', &MCP_PROCESSOR.method(:root_endpoint)
post '/' do
  request.body.rewind
  MCP_PROCESSOR.rpc_endpoint(request.body.read)
end

run Sinatra::Application
