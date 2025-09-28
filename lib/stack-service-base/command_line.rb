require_relative 'version'
require 'open3'
require 'optionparser'

def exec_i(cmd, input_string = nil, &block)
  puts "exec_i(inputs.size #{input_string&.size}): #{cmd}"
  Open3.popen3(cmd) do |i, o, e, wait_thr|
    std_out, std_err = '', ''
    i.puts input_string unless input_string.nil?
    i.close
    while line = o.gets; puts "o: #{line}"; std_out += "#{line}\n" end
    while line = e.gets; puts "o: #{line}"; std_err += "#{line}\n" end
    return_value = wait_thr.value
    puts "Error level was: #{return_value.exitstatus}" unless return_value.success?

    if block_given?
      block.call return_value, std_out, std_err
    else
      exit return_value.exitstatus unless return_value.success?
    end
  end
end

def exec_o_lines(cmd,&)
  IO.popen(cmd, 'r') do |f|
    f.each_line do |line|
      yield line
    end
  end
end

module SSBase
  module CommandLine
    COMMANDS = {}

    class << self
      def run(args)
        params = {}

        a, extra = ARGV.join(' ').split( / -- /)
        ARGV.replace a.split if a
        ARGV << '-h' if ARGV.empty?

        OptionParser.new do |o|
          o.version = "#{StackServiceBase::VERSION}"

          usage = [
            'ssbase [options] COMMAND',
          ]
          o.banner = "Version: #{o.version}\nUsage:\n\t#{usage.join "\n\t"}"
          o.separator ''
          o.separator 'Commands:'
          COMMANDS.each { |name, cmd| o.separator "#{' ' * 5}#{name} -  #{[cmd.help].flatten.join "\n#{' ' * (5+4 + name.size)}" }" }

          o.separator ''
          o.separator 'Options:'

          COMMANDS.values.select{_1.options(o) if _1.respond_to? :options }

          o.on('-h', '--help') { puts o; exit }
          o.parse! args, into: params

          params.transform_keys!{_1.to_s.gsub('-','_').to_sym}

          command = args.shift || ''
          raise "Unknown command: #{command}" unless COMMANDS.key?(command.to_sym)

          COMMANDS[command.to_sym].run [], params, args, extra
        rescue => e
          puts e.message
          ENV['DEBUG'] ? raise : exit(1)
        end
      end
    end
  end
end
