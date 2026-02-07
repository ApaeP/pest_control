# frozen_string_literal: true

require "rails_helper"

RSpec.describe PestControl do
  describe ".configure" do
    it "yields configuration block" do
      described_class.configure do |config|
        config.ban_duration = 12.hours
        config.fake_site_name = "Test Site"
      end

      expect(described_class.configuration.ban_duration).to eq(12.hours)
      expect(described_class.configuration.fake_site_name).to eq("Test Site")
    end
  end

  describe "IP banning" do
    let(:ip) { "192.168.1.100" }

    describe ".ban_ip!" do
      it "bans an IP with a reason" do
        described_class.ban_ip!(ip, "test_reason")

        expect(described_class.banned?(ip)).to be true
      end

      it "does not ban when banning is disabled" do
        described_class.configuration.banning_enabled = false

        described_class.ban_ip!(ip, "test_reason")

        expect(described_class.banned?(ip)).to be false
      end

      it "calls on_ip_banned callback" do
        callback_called = false
        described_class.configuration.on_ip_banned = ->(banned_ip, reason) {
          callback_called = true
          expect(banned_ip).to eq(ip)
          expect(reason).to eq("test_reason")
        }

        described_class.ban_ip!(ip, "test_reason")

        expect(callback_called).to be true
      end
    end

    describe ".banned?" do
      it "returns false for non-banned IPs" do
        expect(described_class.banned?("1.2.3.4")).to be false
      end

      it "returns true for banned IPs" do
        described_class.ban_ip!(ip, "test")
        expect(described_class.banned?(ip)).to be true
      end

      it "returns false for expired bans" do
        ban_key = "#{described_class.configuration.cache_key_prefix}:ban:#{ip}"
        expired_ban = {
          banned_at: 2.days.ago.iso8601,
          reason: "test",
          expires_at: 1.day.ago.iso8601,
        }
        Rails.cache.write(ban_key, expired_ban)

        expect(described_class.banned?(ip)).to be false
      end
    end

    describe ".unban_ip!" do
      it "removes an IP from the ban list" do
        described_class.ban_ip!(ip, "test")
        expect(described_class.banned?(ip)).to be true

        described_class.unban_ip!(ip)
        expect(described_class.banned?(ip)).to be false
      end
    end

    describe ".clear_all_bans!" do
      it "clears all bans and logs success" do
        described_class.ban_ip!(ip, "test")
        expect(described_class.banned?(ip)).to be true

        expect(described_class).to receive(:log).with(:info, /All bans cleared/)
        described_class.clear_all_bans!

        expect(described_class.banned?(ip)).to be false
      end
    end

    describe ".banned_ips" do
      it "returns a hash of all banned IPs" do
        described_class.ban_ip!("1.1.1.1", "reason1")
        described_class.ban_ip!("2.2.2.2", "reason2")

        result = described_class.banned_ips
        expect(result.keys).to contain_exactly("1.1.1.1", "2.2.2.2")
        expect(result["1.1.1.1"][:reason]).to eq("reason1")
      end

      it "returns parsed Time objects for banned_at and expires_at" do
        described_class.ban_ip!("3.3.3.3", "test_reason")

        result = described_class.banned_ips
        info = result["3.3.3.3"]

        expect(info[:banned_at]).to be_a(ActiveSupport::TimeWithZone)
        expect(info[:expires_at]).to be_a(ActiveSupport::TimeWithZone)
        expect(info[:banned_at]).to be_within(2.seconds).of(Time.current)
        expect(info[:expires_at]).to be_within(2.seconds).of(Time.current + described_class.configuration.ban_duration)
      end
    end
  end

  describe "visit counting" do
    let(:ip) { "10.0.0.1" }

    describe ".increment_visit_count" do
      it "increments visit count for an IP" do
        expect(described_class.increment_visit_count(ip)).to eq(1)
        expect(described_class.increment_visit_count(ip)).to eq(2)
        expect(described_class.increment_visit_count(ip)).to eq(3)
      end
    end

    describe ".get_visit_count" do
      it "returns 0 for new IPs" do
        expect(described_class.get_visit_count("new.ip")).to eq(0)
      end

      it "returns current count for tracked IPs" do
        3.times { described_class.increment_visit_count(ip) }
        expect(described_class.get_visit_count(ip)).to eq(3)
      end
    end

    describe ".reset_visit_count" do
      it "resets visit count to 0" do
        3.times { described_class.increment_visit_count(ip) }
        described_class.reset_visit_count(ip)

        expect(described_class.get_visit_count(ip)).to eq(0)
      end
    end
  end

  describe ".calculate_tarpit_delay" do
    before do
      described_class.configuration.tarpit_enabled = true
      described_class.configuration.tarpit_base_delay = 2
      described_class.configuration.tarpit_increment_per_visit = 0.5
      described_class.configuration.tarpit_max_delay = 10
    end

    it "returns 0 when tarpit is disabled" do
      described_class.configuration.tarpit_enabled = false
      expect(described_class.calculate_tarpit_delay(5)).to eq(0)
    end

    it "calculates delay based on visit count" do
      expect(described_class.calculate_tarpit_delay(1)).to eq(2.5)  # 2 + (1 * 0.5)
      expect(described_class.calculate_tarpit_delay(4)).to eq(4.0)  # 2 + (4 * 0.5)
    end

    it "caps delay at max_delay" do
      expect(described_class.calculate_tarpit_delay(100)).to eq(10)
    end
  end

  describe ".should_endless_stream?" do
    let(:ip) { "5.5.5.5" }

    before do
      described_class.configuration.endless_stream_enabled = true
      described_class.configuration.endless_stream_threshold = 3
      described_class.configuration.endless_stream_random_chance = 0 # No random chance
    end

    it "returns false when disabled" do
      described_class.configuration.endless_stream_enabled = false
      5.times { described_class.increment_visit_count(ip) }

      expect(described_class.should_endless_stream?(ip)).to be false
    end

    it "returns false below threshold" do
      2.times { described_class.increment_visit_count(ip) }
      expect(described_class.should_endless_stream?(ip)).to be false
    end

    it "returns true at or above threshold" do
      3.times { described_class.increment_visit_count(ip) }
      expect(described_class.should_endless_stream?(ip)).to be true
    end
  end

  describe "memory mode configuration" do
    describe ".memory_enabled?" do
      it "returns false by default" do
        expect(described_class.memory_enabled?).to be false
      end

      it "returns true when enabled" do
        described_class.configuration.memory_enabled = true
        expect(described_class.memory_enabled?).to be true
      end
    end
  end

  describe "dry run mode" do
    let(:ip) { "192.168.1.100" }

    before do
      described_class.configuration.dry_run = true
      described_class.configuration.banning_enabled = true
    end

    it "does not ban IPs when dry_run is enabled" do
      described_class.ban_ip!(ip, "test_reason")

      expect(described_class.banned?(ip)).to be false
    end

    it "logs the would-be ban" do
      expect(described_class).to receive(:log).with(:info, /DRY RUN/)

      described_class.ban_ip!(ip, "test_reason")
    end

    it "emits ban_skipped metric" do
      metrics_data = nil
      described_class.configuration.on_metrics = ->(data) { metrics_data = data }

      described_class.ban_ip!(ip, "test_reason")

      expect(metrics_data[:event]).to eq(:ban_skipped)
    end
  end

  describe "metrics callbacks" do
    it "calls on_metrics when a bot is trapped" do
      metrics_data = nil
      described_class.configuration.on_metrics = ->(data) { metrics_data = data }

      described_class.notify_bot_trapped(ip: "1.2.3.4", type: "FAKE_LOGIN_VIEW")

      expect(metrics_data[:event]).to eq(:trap)
      expect(metrics_data[:ip]).to eq("1.2.3.4")
    end

    it "calls on_metrics when an IP is banned" do
      metrics_data = nil
      described_class.configuration.on_metrics = ->(data) { metrics_data = data }

      described_class.ban_ip!("1.2.3.4", "test")

      expect(metrics_data[:event]).to eq(:ban)
    end
  end

  describe ".notify_bot_trapped" do
    let(:trap_data) do
      {
        ip: "192.168.1.1",
        type: "FAKE_LOGIN_VIEW",
        path: "/wp-login.php",
      }
    end

    it "calls on_bot_trapped callback" do
      callback_called = false
      described_class.configuration.on_bot_trapped = ->(_data) { callback_called = true }

      described_class.notify_bot_trapped(trap_data)

      expect(callback_called).to be true
    end

    context "when memory mode is enabled" do
      before { described_class.configuration.memory_enabled = true }

      it "saves trap record to database" do
        expect { described_class.notify_bot_trapped(trap_data) }
          .to change(PestControl::TrapRecord, :count).by(1)
      end
    end

    context "when memory mode is disabled" do
      before { described_class.configuration.memory_enabled = false }

      it "does not save to database" do
        expect { described_class.notify_bot_trapped(trap_data) }
          .not_to change(PestControl::TrapRecord, :count)
      end
    end
  end

  describe "concurrency control" do
    describe ".acquire_stream_slot!" do
      before do
        described_class.configuration.max_concurrent_streams = 2
        Rails.cache.delete(described_class.send(:active_streams_key))
      end

      it "acquires a slot when available" do
        expect(described_class.acquire_stream_slot!).to be true
        expect(described_class.active_streams_count).to eq(1)
      end

      it "returns false when slots are full" do
        described_class.configuration.max_concurrent_streams = 1
        described_class.acquire_stream_slot!

        expect(described_class.acquire_stream_slot!).to be false
      end
    end

    describe ".release_stream_slot!" do
      before do
        described_class.configuration.max_concurrent_streams = 5
        Rails.cache.delete(described_class.send(:active_streams_key))
      end

      it "releases a slot" do
        described_class.acquire_stream_slot!
        expect(described_class.active_streams_count).to eq(1)

        described_class.release_stream_slot!
        expect(described_class.active_streams_count).to eq(0)
      end

      it "does not go below zero" do
        described_class.release_stream_slot!
        expect(described_class.active_streams_count).to eq(0)
      end
    end

    describe ".max_streams_reached?" do
      it "returns true when at capacity" do
        described_class.configuration.max_concurrent_streams = 1
        Rails.cache.delete(described_class.send(:active_streams_key))
        described_class.acquire_stream_slot!

        expect(described_class.max_streams_reached?).to be true
      end

      it "returns false when below capacity" do
        described_class.configuration.max_concurrent_streams = 5
        Rails.cache.delete(described_class.send(:active_streams_key))

        expect(described_class.max_streams_reached?).to be false
      end
    end

    describe ".acquire_tarpit_slot!" do
      before do
        described_class.configuration.max_concurrent_tarpits = 3
        Rails.cache.delete(described_class.send(:active_tarpits_key))
      end

      it "acquires a tarpit slot when available" do
        expect(described_class.acquire_tarpit_slot!).to be true
        expect(described_class.active_tarpits_count).to eq(1)
      end

      it "returns false when tarpit slots are full" do
        described_class.configuration.max_concurrent_tarpits = 1
        described_class.acquire_tarpit_slot!

        expect(described_class.acquire_tarpit_slot!).to be false
      end
    end

    describe ".release_tarpit_slot!" do
      before do
        described_class.configuration.max_concurrent_tarpits = 5
        Rails.cache.delete(described_class.send(:active_tarpits_key))
      end

      it "releases a tarpit slot" do
        described_class.acquire_tarpit_slot!
        described_class.release_tarpit_slot!

        expect(described_class.active_tarpits_count).to eq(0)
      end
    end
  end

  describe ".notify_endless_stream_start" do
    it "calls on_endless_stream_start callback" do
      callback_data = nil
      described_class.configuration.on_endless_stream_start = ->(ip, count) {
        callback_data = { ip: ip, count: count }
      }

      described_class.notify_endless_stream_start("1.2.3.4", 5)

      expect(callback_data[:ip]).to eq("1.2.3.4")
      expect(callback_data[:count]).to eq(5)
    end

    it "emits stream_start metric" do
      metrics_data = nil
      described_class.configuration.on_metrics = ->(data) { metrics_data = data }

      described_class.notify_endless_stream_start("1.2.3.4", 5)

      expect(metrics_data[:event]).to eq(:stream_start)
    end
  end

  describe ".notify_bot_crashed" do
    it "calls on_bot_crashed callback" do
      callback_data = nil
      described_class.configuration.on_bot_crashed = ->(ip, chunks, error) {
        callback_data = { ip: ip, chunks: chunks, error: error }
      }

      error = IOError.new("Connection reset")
      described_class.notify_bot_crashed("1.2.3.4", 100, error)

      expect(callback_data[:ip]).to eq("1.2.3.4")
      expect(callback_data[:chunks]).to eq(100)
    end

    it "logs the crash" do
      expect(described_class).to receive(:log).with(:warn, anything)

      described_class.notify_bot_crashed("1.2.3.4", 100, IOError.new("test"))
    end
  end

  describe "helper methods" do
    describe ".tarpit_enabled?" do
      it "returns configuration value" do
        described_class.configuration.tarpit_enabled = true
        expect(described_class.tarpit_enabled?).to be true

        described_class.configuration.tarpit_enabled = false
        expect(described_class.tarpit_enabled?).to be false
      end
    end

    describe ".capture_credentials?" do
      it "returns true when credentials_storage is not disabled" do
        described_class.configuration.credentials_storage = :hash_password
        expect(described_class.capture_credentials?).to be true
      end

      it "returns false when credentials_storage is disabled" do
        described_class.configuration.credentials_storage = :disabled
        expect(described_class.capture_credentials?).to be false
      end
    end

    describe ".credentials_storage_mode" do
      it "returns the configured storage mode" do
        described_class.configuration.credentials_storage = :username_only
        expect(described_class.credentials_storage_mode).to eq(:username_only)
      end
    end

    describe ".fingerprinting_enabled?" do
      it "returns configuration value" do
        described_class.configuration.fingerprinting_enabled = true
        expect(described_class.fingerprinting_enabled?).to be true

        described_class.configuration.fingerprinting_enabled = false
        expect(described_class.fingerprinting_enabled?).to be false
      end
    end

    describe ".dry_run?" do
      it "returns configuration value" do
        described_class.configuration.dry_run = true
        expect(described_class.dry_run?).to be true

        described_class.configuration.dry_run = false
        expect(described_class.dry_run?).to be false
      end
    end
  end

  describe ".log" do
    it "logs to configured logger" do
      logger = instance_double(Logger)
      described_class.configuration.logger = logger

      allow(logger).to receive(:warn)
      described_class.log(:warn, "test message")
      expect(logger).to have_received(:warn).with("test message")
    end

    it "respects log level" do
      described_class.configuration.log_level = :error
      logger = instance_double(Logger)
      described_class.configuration.logger = logger

      allow(logger).to receive(:info)
      described_class.log(:info, "should not log")
      expect(logger).not_to have_received(:info)
    end
  end

  describe ".cache" do
    it "returns configured cache" do
      expect(described_class.cache).to eq(Rails.cache)
    end
  end

  describe ".sanitize_credentials" do
    let(:raw_credentials) do
      {
        username: "admin",
        password: "secret123",
        remember: "1",
        redirect_to: "/wp-admin",
      }
    end

    context "when credentials_storage is :disabled" do
      before { described_class.configuration.credentials_storage = :disabled }

      it "returns nil" do
        expect(described_class.sanitize_credentials(raw_credentials)).to be_nil
      end
    end

    context "when credentials_storage is :username_only" do
      before { described_class.configuration.credentials_storage = :username_only }

      it "returns only username" do
        result = described_class.sanitize_credentials(raw_credentials)
        expect(result[:username]).to eq("admin")
        expect(result[:password]).to be_nil
        expect(result[:password_hash]).to be_nil
        expect(result[:captured_at]).to be_present
      end
    end

    context "when credentials_storage is :full" do
      before { described_class.configuration.credentials_storage = :full }

      it "returns all credentials in clear" do
        result = described_class.sanitize_credentials(raw_credentials)
        expect(result[:username]).to eq("admin")
        expect(result[:password]).to eq("secret123")
        expect(result[:remember]).to eq("1")
        expect(result[:captured_at]).to be_present
      end
    end

    context "when credentials_storage is :hash_password (default)" do
      before { described_class.configuration.credentials_storage = :hash_password }

      it "returns username in clear and password as SHA256 hash" do
        result = described_class.sanitize_credentials(raw_credentials)
        expect(result[:username]).to eq("admin")
        expect(result[:password]).to be_nil
        expect(result[:password_hash]).to eq(Digest::SHA256.hexdigest("secret123"))
        expect(result[:remember]).to eq("1")
        expect(result[:captured_at]).to be_present
      end

      it "handles nil password" do
        credentials = { username: "admin", password: nil }
        result = described_class.sanitize_credentials(credentials)
        expect(result[:password_hash]).to be_nil
      end

      it "handles empty password" do
        credentials = { username: "admin", password: "" }
        result = described_class.sanitize_credentials(credentials)
        expect(result[:password_hash]).to be_nil
      end
    end

    context "with nil or empty input" do
      it "returns nil for nil input" do
        expect(described_class.sanitize_credentials(nil)).to be_nil
      end

      it "returns nil for empty hash" do
        expect(described_class.sanitize_credentials({})).to be_nil
      end
    end
  end

  describe "default configuration (safe defaults)" do
    let(:config) { PestControl::Configuration.new }

    it "has endless_stream disabled by default" do
      expect(config.endless_stream_enabled).to be false
    end

    it "has endless_stream_random_chance at 0 by default" do
      expect(config.endless_stream_random_chance).to eq(0)
    end

    it "has tarpit_max_delay at 10 by default" do
      expect(config.tarpit_max_delay).to eq(10)
    end

    it "has credentials_storage as :hash_password by default" do
      expect(config.credentials_storage).to eq(:hash_password)
    end

    it "has redacted_headers configured by default" do
      expect(config.redacted_headers).to include("Cookie")
      expect(config.redacted_headers).to include("Authorization")
      expect(config.redacted_headers).to include("X-Api-Key")
    end
  end
end
