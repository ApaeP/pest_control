# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Legacy Redirects", type: :request do
  before(:all) do
    Rails.application.routes.draw do
      mount PestControl::Engine => "/"
    end
  end

  before do
    PestControl.configuration.legacy_redirects_enabled = true
    PestControl.configuration.legacy_extensions = ["php", "xml"]
    PestControl.configuration.legacy_strip_extension = true
    PestControl.configuration.legacy_tolerance = 5
    PestControl.configuration.legacy_mappings = {
      "/periode3.php" => "/periode-3",
      "/feed.xml" => "/rss",
    }
  end

  describe "GET with custom mapping" do
    it "redirects to mapped path with 301" do
      get "/periode3.php"

      expect(response).to have_http_status(:moved_permanently)
      expect(response.location).to end_with("/periode-3")
    end

    it "does not ban the IP" do
      get "/periode3.php"

      expect(PestControl.banned?("127.0.0.1")).to be false
    end

    it "works for XML files too" do
      get "/feed.xml"

      expect(response).to have_http_status(:moved_permanently)
      expect(response.location).to end_with("/rss")
    end
  end

  describe "GET with auto-strip extension" do
    it "redirects /contact.php to /contact" do
      get "/contact.php"

      expect(response).to have_http_status(:moved_permanently)
      expect(response.location).to end_with("/contact")
    end

    it "does not ban the IP" do
      get "/contact.php"

      expect(PestControl.banned?("127.0.0.1")).to be false
    end
  end

  describe "GET unmapped URL within tolerance" do
    before do
      PestControl.configuration.legacy_strip_extension = false
    end

    it "returns 404 without banning for visits within tolerance" do
      4.times do
        get "/unknown.php"
        expect(response).to have_http_status(:not_found)
        expect(PestControl.banned?("127.0.0.1")).to be false
      end
    end

    it "bans after exceeding tolerance" do
      6.times { get "/unknown.php" }

      expect(PestControl.banned?("127.0.0.1")).to be true
    end
  end

  describe "POST requests" do
    it "bans immediately regardless of legacy settings" do
      post "/contact.php"

      expect(PestControl.banned?("127.0.0.1")).to be true
    end
  end

  describe "non-legacy extensions" do
    it "follows normal PestControl behavior" do
      get "/wp-login.php"

      expect(PestControl.banned?("127.0.0.1")).to be true
    end

    context "when php is not in legacy_extensions" do
      before do
        PestControl.configuration.legacy_extensions = ["xml"]
      end

      it "bans PHP requests normally" do
        get "/contact.php"

        expect(PestControl.banned?("127.0.0.1")).to be true
      end
    end
  end

  describe "with legacy_redirects_enabled = false" do
    before do
      PestControl.configuration.legacy_redirects_enabled = false
    end

    it "follows normal PestControl behavior" do
      get "/periode3.php"

      expect(PestControl.banned?("127.0.0.1")).to be true
    end
  end

  describe "logging" do
    before do
      PestControl.configuration.legacy_log_redirects = true
      PestControl.configuration.memory_enabled = true
    end

    it "creates trap record for redirect when logging enabled" do
      expect { get "/periode3.php" }.to change(PestControl::TrapRecord, :count).by(1)

      record = PestControl::TrapRecord.last
      expect(record.trap_type).to eq("legacy_redirect")
      expect(record.path).to eq("/periode3.php")
    end

    context "when logging disabled" do
      before do
        PestControl.configuration.legacy_log_redirects = false
      end

      it "does not create trap record" do
        expect { get "/periode3.php" }.not_to(change(PestControl::TrapRecord, :count))
      end
    end
  end
end
