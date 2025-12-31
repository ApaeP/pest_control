# frozen_string_literal: true

require "rails_helper"

RSpec.describe PestControl::TrapRecord, type: :model do
  describe "validations" do
    it "requires ip" do
      record = described_class.new(trap_type: :fake_login_view)
      expect(record).not_to be_valid
      expect(record.errors[:ip]).to be_present
    end

    it "requires trap_type" do
      record = described_class.new(ip: "1.2.3.4")
      expect(record).not_to be_valid
      expect(record.errors[:trap_type]).to be_present
    end

    it "is valid with ip and trap_type" do
      record = described_class.new(ip: "1.2.3.4", trap_type: :fake_login_view)
      expect(record).to be_valid
    end
  end

  describe "scopes" do
    before do
      described_class.create!(ip: "1.1.1.1", trap_type: :fake_login_view, created_at: 1.day.ago)
      described_class.create!(ip: "1.1.1.1", trap_type: :credential_capture)
      described_class.create!(ip: "2.2.2.2", trap_type: :xmlrpc_attack)
    end

    describe ".recent" do
      it "orders by created_at desc" do
        # Enum returns the key as string
        expect(described_class.recent.first.trap_type).to eq("xmlrpc_attack")
      end
    end

    describe ".today" do
      it "returns only records from today" do
        expect(described_class.today.count).to eq(2)
      end
    end

    describe ".by_ip" do
      it "filters by IP" do
        expect(described_class.by_ip("1.1.1.1").count).to eq(2)
        expect(described_class.by_ip("2.2.2.2").count).to eq(1)
      end
    end

    describe ".by_type" do
      it "filters by trap type (using DB value)" do
        expect(described_class.by_type("FAKE_LOGIN_VIEW").count).to eq(1)
        expect(described_class.by_type("CREDENTIAL_CAPTURE").count).to eq(1)
      end
    end

    describe ".with_credentials" do
      it "filters credential capture records" do
        expect(described_class.with_credentials.count).to eq(1)
      end

      it "includes CREDENTIAL_CAPTURE_BLOCKED records" do
        described_class.create!(ip: "3.3.3.3", trap_type: :credential_capture_blocked)
        expect(described_class.with_credentials.count).to eq(2)
      end
    end
  end

  describe ".record_from_trap_data" do
    let(:trap_data) do
      {
        ip: "192.168.1.1",
        type: "FAKE_LOGIN_VIEW",
        path: "/wp-login.php",
        method: "GET",
        user_agent: "curl/7.64.1",
        visit_count: 3,
      }
    end

    context "when memory mode is disabled" do
      before { PestControl.configuration.memory_enabled = false }

      it "does not create a record" do
        expect { described_class.record_from_trap_data(trap_data) }.not_to change(described_class, :count)
      end
    end

    context "when memory mode is enabled" do
      before { PestControl.configuration.memory_enabled = true }

      it "creates a record from trap data" do
        expect { described_class.record_from_trap_data(trap_data) }.to change(described_class, :count).by(1)

        record = described_class.last
        expect(record.ip).to eq("192.168.1.1")
        # Enum returns the key
        expect(record.trap_type).to eq("fake_login_view")
        # Raw DB value
        expect(record.trap_type_before_type_cast).to eq("FAKE_LOGIN_VIEW")
        expect(record.path).to eq("/wp-login.php")
        expect(record.user_agent).to eq("curl/7.64.1")
        expect(record.visit_count).to eq(3)
      end

      it "saves credentials when present" do
        data_with_creds = trap_data.merge(
          type: "CREDENTIAL_CAPTURE",
          credentials: { username: "admin", password: "password123" }
        )

        described_class.record_from_trap_data(data_with_creds)
        record = described_class.last

        expect(record.credentials).to eq({ "username" => "admin", "password" => "password123" })
      end
    end
  end

  describe ".stats" do
    before do
      described_class.create!(ip: "1.1.1.1", trap_type: :fake_login_view)
      described_class.create!(ip: "1.1.1.1", trap_type: :credential_capture)
      described_class.create!(ip: "2.2.2.2", trap_type: :fake_login_view)
    end

    it "returns stats hash" do
      stats = described_class.stats

      expect(stats[:total]).to eq(3)
      expect(stats[:unique_ips]).to eq(2)
      # group(:trap_type) returns enum keys
      expect(stats[:by_type]).to eq({ "fake_login_view" => 2, "credential_capture" => 1 })
      expect(stats[:credentials_captured]).to eq(1)
      expect(stats[:top_ips].keys).to include("1.1.1.1")
    end
  end

  describe "instance methods" do
    let(:record) { described_class.create!(ip: "1.1.1.1", trap_type: :credential_capture) }

    describe "#trap_type_label" do
      it "returns human-readable label" do
        expect(record.trap_type_label).to eq("Credential Capture")
      end
    end

    describe "#trap_type_badge_class" do
      it "returns badge class based on trap type" do
        expect(record.trap_type_badge_class).to eq("badge-red")

        login_record = described_class.create!(ip: "2.2.2.2", trap_type: :fake_login_view)
        expect(login_record.trap_type_badge_class).to eq("badge-green")
      end
    end
  end

  describe ".search" do
    before do
      described_class.create!(ip: "192.168.1.1", trap_type: :fake_login_view, path: "/wp-login.php",
                              user_agent: "curl/7.64.1")
      described_class.create!(ip: "10.0.0.1", trap_type: :xmlrpc_attack, path: "/xmlrpc.php",
                              user_agent: "python-requests")
    end

    it "searches by IP" do
      expect(described_class.search("192.168").count).to eq(1)
    end

    it "searches by path" do
      expect(described_class.search("xmlrpc").count).to eq(1)
    end

    it "searches by user agent" do
      expect(described_class.search("curl").count).to eq(1)
    end

    it "returns all records for blank query" do
      expect(described_class.search("").count).to eq(2)
      expect(described_class.search(nil).count).to eq(2)
    end
  end
end
