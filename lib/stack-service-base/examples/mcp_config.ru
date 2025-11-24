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

require 'stack-service-base/mcp/mcp_helper'
helpers McpHelper

Tool :search do
  description 'Search for a term in the database'
  input query: { type: "string", description: "Term to search for", required: true }
  call do |inputs|
    query = inputs[:query]
    { results: [{id:"doc-1",title:"...",url:"..."}] }
  end
end

Tool :fetch do
  description 'Fetch a resource from the database'
  input resource_id: { type: "string", description: "Resource ID to fetch", required: true }
  call do |inputs|
    id = inputs[:id]
    { id: "doc-1", title: "...", text: "full text...", url: "https://example.com/doc",  metadata: { source: "vector_store" } }
  end
end

Tool :service_status do
  description 'Check current status of a service'
  input service_name: { type: "string", description: "Service name to inspect", required: true }
  call do |inputs|
    service_name = inputs[:service_name]
    service = SERVICES[service_name]
    rpc_error!(-32000, "Unknown service #{service_name}") unless service
    {
      service_name: service_name,
      status: service[:status],
      uptime_sec: service[:uptime],
      last_restart: service[:last_restart].utc.iso8601,
    }
  end
end

Tool :restart_service do
  description 'Restart a service'
  input service_name: { type: "string", description: "Service name to restart", required: true },
        force: { type: "boolean", default: false, description: "Force restart if graceful fails" }
  call do |inputs|
    service_name = inputs[:service_name]
    service = SERVICES[service_name]
    rpc_error!(-32000, "Unknown service #{service_name}") unless service

    service[:status]       = "running"
    service[:last_restart] = Time.now
    service[:uptime]       = 0
    {
      service_name: service_name,
      status: service[:status],
      restarted_at: service[:last_restart].utc.iso8601,
      force: inputs.fetch(:force, false)
    }
  end
end

run Sinatra::Application
