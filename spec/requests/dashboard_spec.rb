# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PestControl::DashboardController", type: :request do
  before(:all) do
    Rails.application.routes.draw do
      mount PestControl::Engine => "/"
    end
  end

  before do
    PestControl.configuration.memory_enabled = true
    PestControl.configuration.dashboard_auth = ->(_controller) { true }
  end

  describe "GET /pest-control/lab" do
    context "with no data (zero records, no banned IPs)" do
      it "renders successfully without FloatDomainError" do
        get "/pest-control/lab"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Pest Control Lab")
      end
    end

    context "with trap records" do
      before do
        PestControl::TrapRecord.create!(ip: "1.2.3.4", trap_type: "FAKE_LOGIN_VIEW", path: "/wp-login.php")
        PestControl::TrapRecord.create!(ip: "5.6.7.8", trap_type: "CREDENTIAL_CAPTURE", path: "/wp-login.php")
      end

      it "renders successfully with data" do
        get "/pest-control/lab"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Pest Control Lab")
        expect(response.body).to include("1.2.3.4")
      end
    end

    context "with banned IPs" do
      before do
        PestControl::TrapRecord.create!(ip: "9.9.9.9", trap_type: "FAKE_LOGIN_VIEW", path: "/wp-login.php")
        PestControl.ban_ip!("9.9.9.9", "test")
      end

      it "renders the banned IPs section with parsed times" do
        get "/pest-control/lab"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Currently Banned IPs")
        expect(response.body).to include("9.9.9.9")
      end
    end
  end
end
