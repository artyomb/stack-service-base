require_relative 'lib/version'

Gem::Specification.new do |s|
  s.name        = 'stack-service-base'
  s.version     = StackServiceBase::Base::VERSION
  s.summary     = 'Common files'
  s.authors     = ['']
  s.require_paths = ['.']
  s.files       = Dir['{bin,lib,test,examples}/**/*']
  s.require_paths = ['lib']

  s.required_ruby_version = ">= " + File.read(File.dirname(__FILE__)+'/.ruby-version').strip

  s.add_dependency 'prometheus-client'
end


