require 'sequel'
require 'sinatra'
require 'stack-service-base'

StackServiceBase.rack_setup self

DB = Sequel.connect ENV.fetch('DB_URL')

# require Models ...
# require_relative 'models/...'

get '/', &-> { slim :index }

get '/api/foo' do
  content_type :json
  {status: 'Ok'}.to_json
end

post '/api/create' do
  _form_data = JSON request.body.read, symbolize_names: true

  # Model.create _form_data

  content_type :json
  {message: 'Created successfully'}.to_json
end


helpers do
  def download(url)
    response = HTTParty.get(url)
    response.body

    halt 400, { message: 'Invalid input data', errors: errors }.to_json unless errors.empty?
  end
end

run Sinatra::Application