require_relative 'command_line'
require 'fileutils'

SSBase::CommandLine::COMMANDS[:init] = Class.new do
  def options(parser)
    parser.on('', '--gitlab-c', 'Gitlab C CI/CD')
    parser.on('', '--gitlab',   'Gitlab CI/CD')
    parser.on('', '--github',   'GitHub CI/CD')
  end

  def run(obj, params, args, _extra)
    if params.empty? || args.empty?
      puts 'Usage: ssbase init [option] <service name>'
      puts 'option: --gitlab-c, --gitlab, --github'
      return
    end


    copy_folder :home

    copy_folder 'gitlab-c' if params[:gitlab_c]
    copy_folder 'gitlab' if params[:gitlab]
    copy_folder 'github' if params[:github]

    update_service_name args.shift
  end

  def cp_r(src, dst)
    # Mimics cp -rn src/. dst/ behavior.
    Dir.glob("#{src}/**/{*,.*}", File::FNM_DOTMATCH).each do |source_path|
      next if ['.', '..'].include?(File.basename(source_path))

      rel_path = source_path.sub(/^#{Regexp.escape(src)}\/?/, '')
      dest_path = File.join(dst, rel_path)

      next if File.exist?(dest_path)

      if File.directory?(source_path)
        FileUtils.mkdir_p(dest_path, verbose: true)
      else
        $stdout.puts "add -> #{dest_path}"
        FileUtils.cp(source_path, dest_path)
      end
    end
  end


  def copy_folder( f_name)
    $stdout.puts "Copy template: #{f_name}"
    cp_r "#{__dir__}/project_template/#{f_name}/.", '.'
    # FileUtils.cp_r "#{__dir__}/project_template/#{f_name}/.", '.', verbose: true
    # system "cp -rv --update=none #{__dir__}/project_template/#{f_name}/. ."
    #system "rsync -av --ignore-existing --info=NAME,progress0,stats0  #{__dir__}/project_template/#{f_name}/ ./  | grep -v '^sending incremental file list$'  | grep -v '/$' "
  end

  def update_service_name(s_name)
    $stdout.puts "Update service name: #{s_name}"
    Dir.glob('**/*').each do |file|
      next unless File.file? file
      content = File.read(file)
      include = content.include?('${service_name}') ? '(found)' : nil
      next unless include
      $stdout.puts "update file: #{file} #{include}"
      content.gsub!(/\$\{service_name\}/, s_name)
      File.write(file, content)
    end
  end

  def help = ['Create basic service file structure',
              '[... to_compose <deploy name>] ']
end.new


