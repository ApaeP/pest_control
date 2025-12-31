# frozen_string_literal: true

require "rails_helper"

RSpec.describe PestControl::RackAttackRules do
  before do
    # Mock Rack::Attack if not defined
    unless defined?(Rack::Attack)
      stub_const("Rack::Attack", Class.new do
        class << self
          attr_accessor :blocklist_procs, :throttle_procs, :blocklisted_responder, :throttled_responder

          def blocklist(name, &block)
            @blocklist_procs ||= {}
            @blocklist_procs[name] = block
          end

          def throttle(name, options = {}, &block)
            @throttle_procs ||= {}
            @throttle_procs[name] = { options: options, block: block }
          end
        end
      end)
    end
  end

  describe ".apply!" do
    it "configures Rack::Attack rules" do
      expect { described_class.apply! }.not_to raise_error
    end

    it "registers a blocklist for banned IPs" do
      described_class.apply!
      expect(Rack::Attack.blocklist_procs).to have_key("pest_control/banned_ips")
    end

    it "registers a throttle for suspicious user agents" do
      described_class.apply!
      expect(Rack::Attack.throttle_procs).to have_key("pest_control/suspicious_ua")
    end

    it "sets blocklisted_responder" do
      described_class.apply!
      expect(Rack::Attack.blocklisted_responder).to be_a(Proc)
    end

    it "sets throttled_responder" do
      described_class.apply!
      expect(Rack::Attack.throttled_responder).to be_a(Proc)
    end
  end

  describe "blocklist behavior" do
    before { described_class.apply! }

    let(:blocklist_proc) { Rack::Attack.blocklist_procs["pest_control/banned_ips"] }

    it "blocks banned IPs" do
      PestControl.ban_ip!("1.2.3.4", "test")
      req = Struct.new(:ip, :path, :post?).new("1.2.3.4", "/some-path", false)

      result = blocklist_proc.call(req)
      expect(result).to be true
    end

    it "does not block non-banned IPs" do
      req = Struct.new(:ip, :path).new("5.6.7.8", "/some-path")

      result = blocklist_proc.call(req)
      expect(result).to be false
    end

    it "does not block pest-control routes" do
      PestControl.ban_ip!("1.2.3.4", "test")
      req = Struct.new(:ip, :path).new("1.2.3.4", "/pest-control/lab")

      result = blocklist_proc.call(req)
      expect(result).to be false
    end

    it "does not block /pest-control exactly" do
      PestControl.ban_ip!("1.2.3.4", "test")
      req = Struct.new(:ip, :path).new("1.2.3.4", "/pest-control")

      result = blocklist_proc.call(req)
      expect(result).to be false
    end
  end

  describe "throttle behavior" do
    before { described_class.apply! }

    let(:throttle_config) { Rack::Attack.throttle_procs["pest_control/suspicious_ua"] }
    let(:throttle_proc) { throttle_config[:block] }

    it "throttles suspicious user agents" do
      PestControl.configuration.suspicious_user_agents = [/curl/i, /wget/i]
      req = Struct.new(:ip, :user_agent).new("1.2.3.4", "curl/7.64.1")

      result = throttle_proc.call(req)
      expect(result).to eq("1.2.3.4")
    end

    it "does not throttle normal user agents" do
      PestControl.configuration.suspicious_user_agents = [/curl/i, /wget/i]
      req = Struct.new(:ip, :user_agent).new("1.2.3.4", "Mozilla/5.0")

      result = throttle_proc.call(req)
      expect(result).to be_nil
    end
  end

  describe "blocklisted_responder" do
    before do
      PestControl.configuration.tarpit_enabled = false
      described_class.apply!
    end

    it "returns 403 status" do
      env = { "REQUEST_METHOD" => "GET", "PATH_INFO" => "/test" }
      responder = Rack::Attack.blocklisted_responder

      status, headers, body = responder.call(env)

      expect(status).to eq(403)
      expect(headers["Content-Type"]).to eq("text/html")
      expect(headers["X-Robots-Tag"]).to eq("noindex, nofollow")
      expect(body.first).to include("403 Forbidden")
    end

    it "uses custom blocked HTML when configured" do
      PestControl.configuration.custom_blocked_html = "<h1>Custom Block</h1>"
      described_class.apply!

      env = { "REQUEST_METHOD" => "GET", "PATH_INFO" => "/test" }
      responder = Rack::Attack.blocklisted_responder

      _, _, body = responder.call(env)
      expect(body.first).to eq("<h1>Custom Block</h1>")
    end
  end

  describe "throttled_responder" do
    before { described_class.apply! }

    it "returns 429 status" do
      env = { "rack.attack.match_data" => { period: 60 } }
      responder = Rack::Attack.throttled_responder

      status, headers, body = responder.call(env)

      expect(status).to eq(429)
      expect(headers["Retry-After"]).to eq("60")
      expect(body.first).to include("Rate limit exceeded")
    end

    it "handles missing match data" do
      env = {}
      responder = Rack::Attack.throttled_responder

      status, headers, = responder.call(env)

      expect(status).to eq(429)
      expect(headers["Retry-After"]).to eq("")
    end
  end

  describe "credential capture from banned IP" do
    before do
      described_class.apply!
      PestControl.configuration.memory_enabled = true
    end

    let(:blocklist_proc) { Rack::Attack.blocklist_procs["pest_control/banned_ips"] }

    it "captures credentials when banned IP posts login data" do
      PestControl.ban_ip!("1.2.3.4", "test")

      params_hash = { "log" => "admin", "pwd" => "secret" }
      request_struct = Struct.new(:ip, :path, :post?, :request_method, :user_agent, :referer, :host, :params,
                                  keyword_init: true)
      req = request_struct.new(
        ip: "1.2.3.4", path: "/wp-login.php", post?: true, request_method: "POST",
        user_agent: "Mozilla/5.0", referer: nil, host: "example.com", params: params_hash
      )

      expect do
        blocklist_proc.call(req)
      end.to change(PestControl::TrapRecord, :count).by(1)
    end

    it "does not capture empty credentials" do
      PestControl.ban_ip!("1.2.3.4", "test")

      req = Struct.new(:ip, :path, :post?, :params, keyword_init: true).new(
        ip: "1.2.3.4", path: "/wp-login.php", post?: true, params: {}
      )

      expect do
        blocklist_proc.call(req)
      end.not_to change(PestControl::TrapRecord, :count)
    end
  end

  describe "tarpit on blocked response" do
    before do
      PestControl.configuration.tarpit_enabled = true
      PestControl.configuration.banned_ip_tarpit_min = 0.001
      PestControl.configuration.banned_ip_tarpit_max = 0.002
      described_class.apply!
    end

    it "applies tarpit delay to blocked requests" do
      env = { "REQUEST_METHOD" => "GET", "PATH_INFO" => "/test" }
      responder = Rack::Attack.blocklisted_responder

      start_time = Time.zone.now
      responder.call(env)
      elapsed = Time.zone.now - start_time

      expect(elapsed).to be >= 0.001
    end
  end
end
