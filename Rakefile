require 'rspec/core/rake_task'
require_relative 'lib/version'

rspec = RSpec::Core::RakeTask.new(:spec)

require 'rubocop/rake_task'

RuboCop::RakeTask.new


task default: %i[rspec]

desc 'CI Rspec run with reports'
task :rspec do |t|
  # rm "coverage.data" if File.exist?("coverage.data")
  rspec.rspec_opts = '--profile --color -f documentation -f RspecJunitFormatter --out ./results/rspec.xml'
  Rake::Task['spec'].invoke
end

require 'erb'

desc 'Update readme'
task :readme do |t|
  puts 'Update readme.erb -> readme.md'
  template = File.read './README.erb'
  renderer = ERB.new template, trim_mode: '-'
  File.write './README.md', renderer.result
end

desc 'Pre commit'
task commit: %i[spec readme]

desc 'Build'
task build: %i[readme] do |t|
  puts 'Build'
  gemspec = Dir['*.gemspec'].first
  system "gem build #{gemspec}" or exit 1
end

desc 'Build&push new version'
task push: %i[readme] do |t|
  puts 'Build&push new version'
  gemspec = Dir['*.gemspec'].first
  system "gem build #{gemspec}" or exit 1
  system "gem install ./stack-service-base-#{StackServiceBase::Base::VERSION}.gem" or exit 1
  # curl -u gempusher https://rubygems.org/api/v1/api_key.yaml > ~/.gem/credentials; chmod 0600 ~/.gem/credentials
  system "gem push stack-service-base-#{StackServiceBase::Base::VERSION}.gem" or exit 1
  system 'gem list -r stack-service-base' or exit 1
end

