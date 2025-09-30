if Bundler.definition.specs.any? { |spec| spec.name == 'sinatra' }
  unless Bundler.definition.specs.any? { |spec| spec.name == 'slim' }
    raise 'When using with Sinatra, gem slim is required'
  end

  require 'sinatra/base'

  module Sinatra
    module SSBaseSinatra
      module AddPublic
        def static!(options={})
          super
          path = File.expand_path "#{__dir__}/public/#{Sinatra::Base::URI_INSTANCE.unescape(request.path_info)}"
          return unless File.file?(path)

          env['sinatra.static_file'] = path
          cache_control(*settings.static_cache_control) if settings.static_cache_control?
          send_file path, options.merge(disposition: nil)
        end
      end
      module FindTemplate
        def find_template(views, name, engine, &block)
          super
          yield File.expand_path "#{__dir__}/views/#{name}.#{@preferred_extension}"
        end
      end

      module MyHelpers
        # include ::HelperFunctions
      end

      def self.registered(app)
        # app.helpers MyHelpers
        Sinatra::Templates.prepend FindTemplate
        Sinatra::Base.prepend AddPublic
        app.set :static, true

        app.get '/ssbase_info' do
          slim :ssbase_info
        end
      end
    end
    register SSBaseSinatra
  end
end