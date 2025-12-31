# frozen_string_literal: true

module PestControl
  module RackAttackRules
    class << self
      def apply!
        return unless defined?(Rack::Attack)

        configure_blocklist
        configure_throttles
        configure_responses
      end

      private

      def configure_blocklist
        Rack::Attack.blocklist("pest_control/banned_ips") do |req|
          next false if pest_control_route?(req.path)

          if PestControl.banned?(req.ip)
            PestControl.log(:warn, "[PEST_CONTROL] 🚫 BLOCKED (banned IP): #{req.ip} -> #{req.path}")

            capture_credentials_from_banned_ip(req) if req.post? && PestControl.memory_enabled?

            true
          else
            false
          end
        end
      end

      def pest_control_route?(path)
        path.start_with?("/pest-control/") || path == "/pest-control"
      end

      def capture_credentials_from_banned_ip(req)
        params = begin
          req.params
        rescue StandardError
          {}
        end
        username = params["log"] || params["username"] || params["user"] || params["email"]
        password = params["pwd"] || params["password"] || params["pass"]

        return unless username.present? || password.present?

        trap_data = {
          ip: req.ip,
          type: "CREDENTIAL_CAPTURE_BLOCKED",
          path: req.path,
          method: req.request_method,
          user_agent: req.user_agent,
          referer: req.referer,
          host: req.host,
          credentials: {
            username: username,
            password: password,
            raw_params: params.except("controller", "action"),
          },
          visit_count: PestControl.get_visit_count(req.ip),
        }

        PestControl.log(:warn, "[PEST_CONTROL] 🔑 CREDENTIALS CAPTURED (banned IP still trying): #{req.ip}")
        PestControl::TrapRecord.record_from_trap_data(trap_data)
      rescue StandardError => e
        PestControl.log(:error, "[PEST_CONTROL] Failed to capture credentials from banned IP: #{e.message}")
      end

      def configure_throttles
        Rack::Attack.throttle("pest_control/suspicious_ua", limit: 10, period: 1.minute) do |req|
          user_agent = req.user_agent.to_s
          patterns = PestControl.configuration.suspicious_user_agents

          if patterns.any? { |pattern| user_agent.match?(pattern) }
            PestControl.log(:debug, "[PEST_CONTROL] 🔍 Suspicious UA: #{req.ip} - #{user_agent.truncate(50)}")
            req.ip
          end
        end
      end

      def configure_responses
        config = PestControl.configuration

        Rack::Attack.blocklisted_responder = ->(env) do
          env_hash = env.respond_to?(:env) ? env.env : env
          request = Rack::Request.new(env_hash)

          if PestControl.tarpit_enabled?
            tarpit_delay = rand(config.banned_ip_tarpit_range)
            sleep(tarpit_delay)
            PestControl.log(:info, "[PEST_CONTROL] 🚫 Tarpit applied: #{request.ip} (#{tarpit_delay}s)")
          end

          html = config.custom_blocked_html || default_blocked_html

          [
            403,
            {
              "Content-Type" => "text/html",
              "X-Robots-Tag" => "noindex, nofollow",
              "Cache-Control" => "no-store",
            },
            [html],
          ]
        end

        Rack::Attack.throttled_responder = ->(env) do
          env_hash = env.respond_to?(:env) ? env.env : env
          retry_after = (env_hash["rack.attack.match_data"] || {})[:period]
          [
            429,
            { "Content-Type" => "text/plain", "Retry-After" => retry_after.to_s },
            ["Rate limit exceeded. Retry later.\n"],
          ]
        end
      end

      def default_blocked_html
        <<~HTML
          <!DOCTYPE html>
          <html>
          <head><title>403 Forbidden</title></head>
          <body>
            <h1>403 Forbidden</h1>
            <p>Your IP has been logged and reported.</p>
            <p>Incident ID: #{SecureRandom.uuid}</p>
          </body>
          </html>
        HTML
      end
    end
  end
end
