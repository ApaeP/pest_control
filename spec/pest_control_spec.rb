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
end
