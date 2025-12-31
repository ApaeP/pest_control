# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PestControl::TrapsController", type: :request do
  before(:all) do
    Rails.application.routes.draw do
      mount PestControl::Engine => "/"
    end
  end

  describe "GET /wp-login.php" do
    it "returns the fake login page" do
      get "/wp-login.php"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("WordPress")
    end

    it "bans the requesting IP" do
      get "/wp-login.php"

      expect(PestControl.banned?("127.0.0.1")).to be true
    end

    it "calls on_bot_trapped callback" do
      trapped_data = nil
      PestControl.configuration.on_bot_trapped = ->(data) { trapped_data = data }

      get "/wp-login.php"

      expect(trapped_data).not_to be_nil
      expect(trapped_data[:type]).to eq("FAKE_LOGIN_VIEW")
      expect(trapped_data[:path]).to eq("/wp-login.php")
    end
  end

  describe "POST /wp-login.php" do
    it "captures credentials when enabled" do
      trapped_data = nil
      PestControl.configuration.on_bot_trapped = ->(data) { trapped_data = data }

      post "/wp-login.php", params: { log: "admin", pwd: "secret123" }

      expect(response).to have_http_status(:ok)
      expect(trapped_data[:type]).to eq("CREDENTIAL_CAPTURE")
      expect(trapped_data[:credentials][:username]).to eq("admin")
      expect(trapped_data[:credentials][:password]).to eq("secret123")
    end

    it "does not capture credentials when disabled" do
      PestControl.configuration.capture_credentials = false
      trapped_data = nil
      PestControl.configuration.on_bot_trapped = ->(data) { trapped_data = data }

      post "/wp-login.php", params: { log: "admin", pwd: "secret123" }

      expect(trapped_data[:credentials]).to be_nil
    end
  end

  describe "GET /wp-admin" do
    it "redirects to wp-login.php" do
      get "/wp-admin"

      expect(response).to have_http_status(:redirect)
      expect(response.location).to include("wp-login.php")
    end
  end

  describe "GET /xmlrpc.php" do
    it "returns fake XML-RPC response" do
      get "/xmlrpc.php"

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("xml")
      expect(response.body).to include("XML-RPC services are disabled")
    end
  end

  describe "GET /*.php (catch-all)" do
    it "returns fake Apache 404" do
      get "/random-file.php"

      expect(response).to have_http_status(:not_found)
      expect(response.body).to include("Apache")
      expect(response.body).to include("Not Found")
    end

    it "works for various PHP paths" do
      ["/admin.php", "/alfa.php", "/shell.php", "/config.php"].each do |path|
        get path
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "GET /wp-content/*" do
    it "returns 404 for WordPress content paths" do
      get "/wp-content/plugins/pwnd.php"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "banned IP behavior" do
    before do
      PestControl.ban_ip!("127.0.0.1", "test_ban")
    end

    it "blocks subsequent requests from banned IPs" do
      expect(PestControl.banned?("127.0.0.1")).to be true
    end
  end

  describe "visit counting integration" do
    it "tracks visits across multiple requests" do
      PestControl.configuration.tarpit_enabled = true
      PestControl.configuration.tarpit_base_delay = 0
      PestControl.configuration.tarpit_increment_per_visit = 0

      trapped_counts = []
      PestControl.configuration.on_bot_trapped = ->(data) {
        trapped_counts << data[:visit_count]
      }

      3.times { get "/wp-login.php" }

      expect(trapped_counts).to eq([1, 2, 3])
    end
  end

  describe "GET /wp-admin/fp.gif (fingerprint capture)" do
    before do
      PestControl.configuration.fingerprinting_enabled = true
    end

    it "returns a transparent GIF" do
      get "/wp-admin/fp.gif"

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("image/gif")
    end

    it "captures fingerprint data from query string" do
      fingerprint = { screen: "1920x1080", tz: "Europe/Paris", lang: "fr" }

      get "/wp-admin/fp.gif?#{CGI.escape(fingerprint.to_json)}"

      cache_key = "#{PestControl.configuration.cache_key_prefix}:fingerprint:127.0.0.1"
      cached_fp = Rails.cache.read(cache_key)

      expect(cached_fp).not_to be_nil
      expect(cached_fp[:screen]).to eq("1920x1080")
    end

    it "returns 404 when fingerprinting is disabled" do
      PestControl.configuration.fingerprinting_enabled = false

      get "/wp-admin/fp.gif"

      expect(response).to have_http_status(:not_found)
    end

    it "handles invalid JSON in query string" do
      get "/wp-admin/fp.gif?not-valid-json"

      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /xmlrpc.php" do
    it "logs XMLRPC attack with body content" do
      trapped_data = nil
      PestControl.configuration.on_bot_trapped = ->(data) { trapped_data = data }

      post "/xmlrpc.php", params: "<methodCall><methodName>test</methodName></methodCall>"

      expect(response).to have_http_status(:ok)
      expect(trapped_data[:type]).to eq("XMLRPC_ATTACK")
    end
  end

  describe "GET /wp-admin/admin-ajax.php" do
    it "redirects to wp-login for admin paths" do
      get "/wp-admin/admin-ajax.php"

      expect(response).to have_http_status(:redirect)
      expect(response.location).to include("wp-login.php")
    end
  end

  describe "overflow handling with tarpit" do
    before do
      PestControl.configuration.tarpit_enabled = true
      PestControl.configuration.max_concurrent_tarpits = 0
    end

    it "rickrolls when tarpits are at capacity with :rickroll action" do
      PestControl.configuration.overflow_action = :rickroll

      get "/random-file.php"

      expect(response).to have_http_status(:redirect)
      expect(response.location).to include("youtube.com")
    end

    it "blocks when tarpits are at capacity with :block action" do
      PestControl.configuration.overflow_action = :block

      get "/random-file.php"

      expect(response).to have_http_status(:forbidden)
    end

    it "redirects to custom URL when configured" do
      PestControl.configuration.overflow_action = "https://example.com/trap"

      get "/random-file.php"

      expect(response).to have_http_status(:redirect)
      expect(response.location).to eq("https://example.com/trap")
    end
  end

  describe "tarpit behavior" do
    before do
      PestControl.configuration.tarpit_enabled = true
      PestControl.configuration.tarpit_base_delay = 0.01
      PestControl.configuration.tarpit_max_delay = 0.02
      PestControl.configuration.tarpit_increment_per_visit = 0.001
    end

    it "applies tarpit delay" do
      start_time = Time.now
      get "/wp-login.php"
      elapsed = Time.now - start_time

      expect(elapsed).to be >= 0.01
    end

    it "increments delay based on visit count" do
      PestControl.configuration.on_bot_trapped = ->(_) {}
      2.times { get "/wp-login.php" }

      visit_count = PestControl.get_visit_count("127.0.0.1")
      expect(visit_count).to eq(2)
    end
  end

  describe "custom login HTML" do
    it "uses custom HTML when configured" do
      PestControl.configuration.custom_login_html = "<h1>Custom Login</h1>"

      get "/wp-login.php"

      expect(response.body).to eq("<h1>Custom Login</h1>")
    end
  end

  describe "dry run mode" do
    before do
      PestControl.configuration.dry_run = true
    end

    it "logs but does not ban in dry run mode" do
      get "/wp-login.php"

      expect(PestControl.banned?("127.0.0.1")).to be false
    end
  end

  describe "metrics emission" do
    it "emits metrics on bot trap" do
      metrics_data = nil
      PestControl.configuration.on_metrics = ->(data) { metrics_data = data }

      get "/wp-login.php"

      expect(metrics_data).not_to be_nil
      expect(metrics_data[:event]).to eq(:ban)
    end
  end

  describe "memory mode integration" do
    before do
      PestControl.configuration.memory_enabled = true
    end

    it "creates TrapRecord when memory is enabled" do
      expect {
        get "/wp-login.php"
      }.to change(PestControl::TrapRecord, :count).by(1)
    end

    it "stores correct trap type" do
      get "/wp-login.php"

      record = PestControl::TrapRecord.last
      expect(record.trap_type).to eq("fake_login_view")
      expect(record.ip).to eq("127.0.0.1")
    end
  end

  describe "endless stream configuration" do
    before do
      PestControl.configuration.endless_stream_enabled = true
      PestControl.configuration.endless_stream_threshold = 100
      PestControl.configuration.endless_stream_random_chance = 0
    end

    it "does not trigger endless stream below threshold" do
      get "/wp-login.php"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("WordPress")
    end
  end

  describe "request headers extraction" do
    it "captures X-Forwarded-For header" do
      trapped_data = nil
      PestControl.configuration.on_bot_trapped = ->(data) { trapped_data = data }

      get "/wp-login.php", headers: { "X-Forwarded-For" => "1.2.3.4, 5.6.7.8" }

      expect(trapped_data[:headers]["X-Forwarded-For"]).to eq("1.2.3.4, 5.6.7.8")
    end

    it "captures Accept-Language header" do
      trapped_data = nil
      PestControl.configuration.on_bot_trapped = ->(data) { trapped_data = data }

      get "/wp-login.php", headers: { "Accept-Language" => "en-US,en;q=0.9" }

      expect(trapped_data[:headers]["Accept-Language"]).to eq("en-US,en;q=0.9")
    end
  end

  describe "POST with credentials" do
    it "captures redirect_to parameter" do
      trapped_data = nil
      PestControl.configuration.on_bot_trapped = ->(data) { trapped_data = data }

      post "/wp-login.php", params: {
        log: "admin",
        pwd: "password",
        rememberme: "forever",
        redirect_to: "http://example.com/wp-admin",
      }

      expect(trapped_data[:credentials][:redirect_to]).to eq("http://example.com/wp-admin")
    end
  end

  describe "fingerprint with memory mode" do
    before do
      PestControl.configuration.fingerprinting_enabled = true
      PestControl.configuration.memory_enabled = true
    end

    it "associates fingerprint with recent trap record" do
      get "/wp-login.php"
      record = PestControl::TrapRecord.last

      fingerprint = { screen: "1920x1080", tz: "UTC" }
      get "/wp-admin/fp.gif?#{CGI.escape(fingerprint.to_json)}"

      record.reload
      expect(record.fingerprint).to eq({ "screen" => "1920x1080", "tz" => "UTC" })
    end
  end
end
