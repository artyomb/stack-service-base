require "json"
require_relative "../support/rack_helper"

RSpec.describe "Integration Tests", type: :request do
  describe "Service basics" do
    it "responds to healthcheck" do
      get "/healthcheck"
      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body.fetch("Status")).to eq("Healthy")
    end
  end
end
