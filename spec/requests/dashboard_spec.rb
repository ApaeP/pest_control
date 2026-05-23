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

  describe "authentication" do
    it "denies access when dashboard_auth returns false" do
      PestControl.configuration.dashboard_auth = ->(_controller) { false }

      get "/pest-control"

      expect(response).to have_http_status(:forbidden)
      expect(response.body).to include("Access Denied")
    end

    it "requires HTTP basic auth when username and password are configured" do
      PestControl.configuration.dashboard_auth = nil
      PestControl.configuration.dashboard_username = "admin"
      PestControl.configuration.dashboard_password = "secret"

      get "/pest-control"
      expect(response).to have_http_status(:unauthorized)

      credentials = ActionController::HttpAuthentication::Basic.encode_credentials("admin", "secret")
      get "/pest-control", headers: { "HTTP_AUTHORIZATION" => credentials }
      expect(response).to have_http_status(:ok)
    end

    it "denies access when authentication is not configured outside development" do
      PestControl.configuration.dashboard_auth = nil
      PestControl.configuration.dashboard_username = nil
      PestControl.configuration.dashboard_password = nil

      get "/pest-control"

      expect(response).to have_http_status(:forbidden)
      expect(response.body).to include("authentication not configured")
    end

    it "allows unauthenticated access in development with a warning" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
      PestControl.configuration.dashboard_auth = nil
      PestControl.configuration.dashboard_username = nil
      PestControl.configuration.dashboard_password = nil

      expect(Rails.logger).to receive(:warn).with(/Dashboard accessed without authentication/)

      get "/pest-control"

      expect(response).to have_http_status(:ok)
    end
  end

  describe "memory mode" do
    it "renders service unavailable when memory mode is disabled" do
      controller = PestControl::DashboardController.new
      allow(PestControl).to receive(:memory_enabled?).and_return(false)
      expect(controller).to receive(:render).with(
        plain: "🧠 Memory Mode is not enabled. Run `rails generate pest_control:memory` first.",
        status: :service_unavailable
      )

      controller.send(:ensure_memory_enabled)
    end
  end

  describe "GET /pest-control" do
    context "with no data (zero records, no banned IPs)" do
      it "renders successfully without FloatDomainError" do
        get "/pest-control"

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
        get "/pest-control"

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
        get "/pest-control"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Currently Banned IPs")
        expect(response.body).to include("9.9.9.9")
      end
    end
  end

  describe "GET /pest-control/records" do
    before do
      PestControl::TrapRecord.create!(
        ip: "1.2.3.4",
        trap_type: "FAKE_LOGIN_VIEW",
        path: "/wp-login.php",
        user_agent: "BotScanner/1.0",
        created_at: 2.days.ago
      )
      PestControl::TrapRecord.create!(
        ip: "5.6.7.8",
        trap_type: "CREDENTIAL_CAPTURE",
        path: "/wp-login.php",
        credentials: { username: "admin" }
      )
      PestControl::TrapRecord.create!(
        ip: "1.2.3.4",
        trap_type: "CATCH_ALL",
        path: "/admin.php"
      )
    end

    it "renders the records index" do
      get "/pest-control/records"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Trap Records")
      expect(response.body).to include("3 records found")
    end

    it "filters by today" do
      get "/pest-control/records", params: { filter: "today" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("2 records found")
      expect(response.body).to include("5.6.7.8")
      expect(response.body).not_to include("BotScanner")
    end

    it "filters by credentials" do
      get "/pest-control/records", params: { filter: "credentials" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("1 record found")
      expect(response.body).to include("5.6.7.8")
    end

    it "filters by unique IPs" do
      get "/pest-control/records", params: { filter: "unique_ips" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("2 records found")
    end

    context "when postgres is the database adapter" do
      before do
        scope = PestControl::TrapRecord.all
        allow(ActiveRecord::Base.connection).to receive(:adapter_name).and_return("PostgreSQL")
        allow(PestControl::TrapRecord).to receive(:recent).and_return(scope)
        allow(scope).to receive(:select).with("DISTINCT ON (ip) *").and_return(scope)
        allow(scope).to receive(:reorder).with("ip, created_at DESC").and_return(scope)
        allow(scope).to receive_messages(count: 0, offset: scope, limit: scope)
      end

      it "uses DISTINCT ON for unique IP filtering" do
        get "/pest-control/records", params: { filter: "unique_ips" }

        expect(response).to have_http_status(:ok)
      end
    end

    it "filters by search query, type, IP, and date range" do
      get "/pest-control/records", params: {
        q: "BotScanner",
        type: "fake_login_view",
        ip: "1.2.3.4",
        from: 3.days.ago.to_date.iso8601,
        to: Date.current.iso8601,
      }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("1 record found")
      expect(response.body).to include("1.2.3.4")
    end

    it "paginates results" do
      51.times do |i|
        PestControl::TrapRecord.create!(ip: "10.0.0.#{i}", trap_type: "CATCH_ALL", path: "/test.php")
      end

      get "/pest-control/records", params: { page: 2 }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("54 records found")
    end
  end

  describe "GET /pest-control/record/:id" do
    let!(:record) do
      PestControl::TrapRecord.create!(ip: "1.2.3.4", trap_type: "FAKE_LOGIN_VIEW", path: "/wp-login.php")
    end

    it "renders the record detail page" do
      get "/pest-control/record/#{record.id}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("1.2.3.4")
      expect(response.body).to include("/wp-login.php")
    end
  end

  describe "POST /pest-control/ban/:ip and /pest-control/unban/:ip" do
    it "bans and unbans an IP from the dashboard" do
      post "/pest-control/ban/8.8.8.8"

      expect(response).to redirect_to("/pest-control")
      expect(PestControl.banned?("8.8.8.8")).to be true

      post "/pest-control/unban/8.8.8.8"

      expect(response).to redirect_to("/pest-control")
      expect(PestControl.banned?("8.8.8.8")).to be false
    end
  end

  describe "GET /pest-control/export" do
    before do
      PestControl::TrapRecord.create!(
        ip: "1.2.3.4",
        trap_type: "CREDENTIAL_CAPTURE",
        path: "/wp-login.php",
        method: "POST",
        user_agent: "Bot/1.0",
        credentials: { username: "admin" }
      )
    end

    it "exports filtered records as CSV" do
      get "/pest-control/export.csv", params: { filter: "credentials", q: "1.2.3.4" }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/csv")
      expect(response.body).to include("id,created_at,ip,trap_type")
      expect(response.body).to include("1.2.3.4")
      expect(response.body).to include("yes")
    end

    it "exports records filtered by today, type, and date range" do
      get "/pest-control/export.csv", params: {
        filter: "today",
        type: "credential_capture",
        from: 1.day.ago.to_date.iso8601,
        to: Date.current.iso8601,
      }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/csv")
    end
  end
end
