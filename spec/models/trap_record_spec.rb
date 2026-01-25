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
        expect(described_class.recent.first.trap_type).to eq("xmlrpc_attack")
      end
    end

    describe ".today" do
      it "returns only records from today" do
        expect(described_class.today.count).to eq(2)
      end
    end

    describe ".yesterday" do
      it "returns only records from yesterday" do
        expect(described_class.yesterday.count).to eq(1)
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
        expect(record.trap_type).to eq("fake_login_view")
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
      described_class.create!(ip: "3.3.3.3", trap_type: :fake_login_view, created_at: 1.day.ago)
    end

    it "returns stats hash" do
      stats = described_class.stats

      expect(stats[:total]).to eq(4)
      expect(stats[:today]).to eq(3)
      expect(stats[:yesterday]).to eq(1)
      expect(stats[:unique_ips]).to eq(3)
      expect(stats[:by_type]).to eq({ "fake_login_view" => 3, "credential_capture" => 1 })
      expect(stats[:credentials_captured]).to eq(1)
      expect(stats[:top_ips].keys).to include("1.1.1.1")
    end
  end

  describe ".daily_stats" do
    before do
      described_class.create!(ip: "1.1.1.1", trap_type: :fake_login_view)
      described_class.create!(ip: "1.1.1.1", trap_type: :credential_capture)
      described_class.create!(ip: "2.2.2.2", trap_type: :fake_login_view, created_at: 1.day.ago)
      described_class.create!(ip: "3.3.3.3", trap_type: :fake_login_view, created_at: 3.days.ago)
    end

    it "returns daily stats for the last 7 days" do
      stats = described_class.daily_stats(days: 7)

      expect(stats.length).to eq(7)
      expect(stats.first[:date]).to eq(6.days.ago.to_date)
      expect(stats.last[:date]).to eq(Date.current)
    end

    it "includes count and credentials for each day" do
      stats = described_class.daily_stats(days: 7)

      today_stats = stats.last
      expect(today_stats[:date]).to eq(Date.current)
      expect(today_stats[:count]).to eq(2)
      expect(today_stats[:credentials]).to eq(1)
    end

    it "returns zero for days with no records" do
      stats = described_class.daily_stats(days: 7)

      empty_day = stats.find { |s| s[:date] == 5.days.ago.to_date }
      expect(empty_day[:count]).to eq(0)
      expect(empty_day[:credentials]).to eq(0)
    end
  end

  describe ".user_agent_stats" do
    before do
      described_class.create!(ip: "1.1.1.1", trap_type: :fake_login_view, user_agent: "curl/7.64.1")
      described_class.create!(ip: "1.1.1.2", trap_type: :fake_login_view, user_agent: "curl/7.64.1")
      described_class.create!(ip: "2.2.2.2", trap_type: :fake_login_view, user_agent: "python-requests")
      described_class.create!(ip: "3.3.3.3", trap_type: :fake_login_view, user_agent: nil)
    end

    it "returns top user agents by count" do
      stats = described_class.user_agent_stats(limit: 10)

      expect(stats.first[:user_agent]).to eq("curl/7.64.1")
      expect(stats.first[:count]).to eq(2)
      expect(stats.first[:percentage]).to eq(50.0)
    end

    it "handles nil user agents as (empty)" do
      stats = described_class.user_agent_stats(limit: 10)

      empty_ua = stats.find { |s| s[:user_agent] == "(empty)" }
      expect(empty_ua).to be_present
      expect(empty_ua[:count]).to eq(1)
    end

    it "respects limit parameter" do
      stats = described_class.user_agent_stats(limit: 2)
      expect(stats.length).to eq(2)
    end

    it "returns empty array when no records" do
      described_class.delete_all
      expect(described_class.user_agent_stats).to eq([])
    end
  end

  describe ".hourly_heatmap" do
    before do
      described_class.create!(ip: "1.1.1.1", trap_type: :fake_login_view)
      described_class.create!(ip: "2.2.2.2", trap_type: :fake_login_view)
    end

    it "returns a 7x24 matrix" do
      heatmap = described_class.hourly_heatmap

      expect(heatmap.keys).to eq((0..6).to_a)
      heatmap.each_value do |hours|
        expect(hours.keys).to eq((0..23).to_a)
      end
    end

    it "counts records by day of week and hour" do
      heatmap = described_class.hourly_heatmap
      current_dow = Time.current.wday
      current_hour = Time.current.hour

      expect(heatmap[current_dow][current_hour]).to eq(2)
    end
  end

  describe ".compare_period" do
    before do
      described_class.create!(ip: "1.1.1.1", trap_type: :fake_login_view)
      described_class.create!(ip: "1.1.1.2", trap_type: :fake_login_view)
      described_class.create!(ip: "2.2.2.2", trap_type: :fake_login_view, created_at: 1.day.ago)
    end

    it "compares today vs yesterday" do
      result = described_class.compare_period(period: :day)

      expect(result[:current]).to eq(2)
      expect(result[:previous]).to eq(1)
      expect(result[:change]).to eq(1)
      expect(result[:percentage]).to eq(100.0)
    end

    it "returns nil percentage when previous is zero" do
      described_class.where(created_at: 1.day.ago.all_day).delete_all
      result = described_class.compare_period(period: :day)

      expect(result[:previous]).to eq(0)
      expect(result[:percentage]).to be_nil
    end

    it "supports week period" do
      result = described_class.compare_period(period: :week)

      expect(result).to have_key(:current)
      expect(result).to have_key(:previous)
      expect(result).to have_key(:change)
      expect(result).to have_key(:percentage)
    end

    it "supports month period" do
      result = described_class.compare_period(period: :month)

      expect(result).to have_key(:current)
      expect(result).to have_key(:previous)
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

  describe ".expired" do
    before do
      PestControl.configuration.trap_records_retention = 1.year
    end

    it "returns records older than retention period" do
      old_record = described_class.create!(ip: "1.1.1.1", trap_type: :fake_login_view, created_at: 2.years.ago)
      new_record = described_class.create!(ip: "2.2.2.2", trap_type: :fake_login_view, created_at: 1.day.ago)

      expired = described_class.expired
      expect(expired).to include(old_record)
      expect(expired).not_to include(new_record)
    end

    it "returns empty when retention is nil" do
      PestControl.configuration.trap_records_retention = nil
      described_class.create!(ip: "1.1.1.1", trap_type: :fake_login_view, created_at: 10.years.ago)

      expect(described_class.expired).to be_empty
    end
  end

  describe ".cleanup_expired!" do
    before do
      PestControl.configuration.trap_records_retention = 1.year
    end

    it "deletes expired records" do
      described_class.create!(ip: "1.1.1.1", trap_type: :fake_login_view, created_at: 2.years.ago)
      described_class.create!(ip: "2.2.2.2", trap_type: :fake_login_view, created_at: 1.day.ago)

      expect { described_class.cleanup_expired! }.to change(described_class, :count).by(-1)
    end

    it "returns count of deleted records" do
      described_class.create!(ip: "1.1.1.1", trap_type: :fake_login_view, created_at: 2.years.ago)
      described_class.create!(ip: "2.2.2.2", trap_type: :fake_login_view, created_at: 3.years.ago)

      result = described_class.cleanup_expired!
      expect(result).to eq(2)
    end
  end

  describe "legacy trap types" do
    it "supports legacy_redirect type" do
      record = described_class.create!(ip: "1.1.1.1", trap_type: :legacy_redirect)
      expect(record.trap_type).to eq("legacy_redirect")
    end

    it "supports legacy_tolerated type" do
      record = described_class.create!(ip: "1.1.1.1", trap_type: :legacy_tolerated)
      expect(record.trap_type).to eq("legacy_tolerated")
    end
  end
end
