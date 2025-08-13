require_relative 'lib/version'

Gem::Specification.new do |s|
  s.name        = 'stack-service-base'
  s.version     = StackServiceBase::Base::VERSION
  s.executables << 'ssbase'
  s.summary     = 'Common files'
  s.authors     = ['Artyom B']
  s.bindir        = 'bin'
  s.require_paths = ['lib']
  s.files = Dir['{bin,lib,test,examples}/{**,.**}/{*,.*}']
  s.require_paths = ['lib']

  s.required_ruby_version = ">= " + File.read(File.dirname(__FILE__)+'/.ruby-version').strip

  s.add_dependency 'rack'
  s.add_dependency 'async'
  s.add_dependency 'prometheus-client'
  s.add_dependency 'opentelemetry-sdk'
  s.add_dependency 'opentelemetry-exporter-otlp'
  s.add_dependency 'opentelemetry-instrumentation-all'
  s.add_dependency 'nats-pure'
  s.add_dependency 'websocket'

  s.add_development_dependency "rake", "~> 13.0"
  s.add_development_dependency "rspec", "~> 3.10"
  s.add_development_dependency "rubocop", "~> 1.63.2"
  s.add_development_dependency "rubocop-rake", "~> 0.6.0"
  s.add_development_dependency "rubocop-rspec", "~> 2.14.2"
  s.add_development_dependency "rspec_junit_formatter", "~> 0.5.1"

end

