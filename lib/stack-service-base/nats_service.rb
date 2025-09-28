require "nats"

NATS_ENABLED = ENV['NATS_URL'].to_s != ''

NATS_URL = ENV['NATS_URL']# || 'nats://nats_single:4222'
NATS_STACK_NAME = ENV['STACK_NAME'] || 'undefined_stack'
NATS_SERVICE_NAME = ENV['STACK_SERVICE_NAME'] || 'undefined_service'

ENV['NATS_RECONNECT'] ||= 'true'
ENV['NATS_RECONNECT_TIME_WAIT'] ||= '1000'
ENV['NATS_MAX_RECONNECT_ATTEMPTS'] ||= '-1'

module NATS
  def nats_client = $nats_client
end

$nats_client = nil

def initialize_nats_service
  LOGGER.info "Initializing NATS service"

  $nats_client = NATS.connect NATS_URL

  service = $nats_client.services.add(
    name: "#{NATS_SERVICE_NAME}_#{NATS_STACK_NAME}",
    version: "1.0.0",
    description: "service-base auto service"
  )

  service.on_stop do
    puts "Service stopped at #{Time.now}"
  end

  service.endpoints.add("min") do |message|
    min = JSON.parse(message.data).min
    message.respond(min.to_json)
  end

  service.endpoints.add("max") do |message|
    max = JSON.parse(message.data).max
    message.respond(max.to_json)
  end

  min = $nats_client.request("min", [5, 100, -7, 34].to_json, timeout: 10)
  max = $nats_client.request("max", [5, 100, -7, 34].to_json, timeout: 10)

  puts "min = #{min.data}, max = #{max.data}"

  # service.stop

end