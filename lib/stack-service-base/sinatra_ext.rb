if Bundler.definition.specs.any? { |spec| spec.name == 'sinatra' }
  unless Bundler.definition.specs.any? { |spec| spec.name == 'slim' }
    raise 'When using with Sinatra, gem slim is required'
  end

  require 'sinatra/base'

  module Sinatra
    module SSBaseSinatra
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
        app.get '/ssbase_info' do
          slim :ssbase_info
        end
      end
    end
    register SSBaseSinatra
  end
end