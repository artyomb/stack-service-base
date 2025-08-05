RSpec.describe 'Integration Tests' do

  describe 'Service basics' do
    it 'respond to Healthcheck' do
      get '/healthcheck'
      expect(last_response.status).to eq(200)
    end
  end
end