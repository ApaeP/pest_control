# frozen_string_literal: true

require "pest_control/version"
require "pest_control/configuration"
require "pest_control/engine"
require "pest_control/rack_attack_rules"

module PestControl
  class << self
    attr_writer :configuration

    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def logger
      configuration.logger || Rails.logger
    end

    def cache
      configuration.cache || Rails.cache
    end

    def log(level, message)
      return unless logger

      case configuration.log_level
      when :debug then logger.send(level, message)
      when :info then logger.send(level, message) if [:info, :warn, :error].include?(level)
      when :warn then logger.send(level, message) if [:warn, :error].include?(level)
      when :error then logger.send(level, message) if level == :error
      else logger.send(level, message)
      end
    end

    def sentry_enabled?
      configuration.sentry_enabled && defined?(Sentry)
    end

    def banning_enabled?
      configuration.banning_enabled
    end

    def endless_stream_enabled?
      configuration.endless_stream_enabled
    end

    def tarpit_enabled?
      configuration.tarpit_enabled
    end

    def capture_credentials?
      configuration.capture_credentials
    end

    def fingerprinting_enabled?
      configuration.fingerprinting_enabled
    end

    def memory_enabled?
      configuration.memory_enabled
    end

    def ban_ip!(ip, reason = "wordpress_scan")
      return unless banning_enabled?

      banned_ips = cache.read(banned_ips_key) || {}
      banned_ips[ip] = {
        banned_at: Time.current,
        reason: reason,
        expires_at: Time.current + configuration.ban_duration
      }
      cache.write(banned_ips_key, banned_ips)

      log(:warn, "[PEST_CONTROL] 🔨 IP BANNED: #{ip} - Reason: #{reason}")

      configuration.on_ip_banned&.call(ip, reason)
    end

    def banned?(ip)
      return false unless banning_enabled?

      banned_ips = cache.read(banned_ips_key) || {}
      ban_info = banned_ips[ip]
      return false unless ban_info

      if ban_info[:expires_at] < Time.current
        banned_ips.delete(ip)
        cache.write(banned_ips_key, banned_ips)
        false
      else
        true
      end
    end

    def banned_ips
      cache.read(banned_ips_key) || {}
    end

    def unban_ip!(ip)
      banned_ips = cache.read(banned_ips_key) || {}
      banned_ips.delete(ip)
      cache.write(banned_ips_key, banned_ips)
      log(:info, "[PEST_CONTROL] ✅ IP unbanned: #{ip}")
    end

    def clear_all_bans!
      cache.delete(banned_ips_key)
      log(:info, "[PEST_CONTROL] ✅ All IPs have been unbanned")
    end

    def increment_visit_count(ip)
      key = visit_count_key(ip)
      count = (cache.read(key) || 0) + 1
      cache.write(key, count, expires_in: configuration.visit_count_ttl)
      count
    end

    def get_visit_count(ip)
      cache.read(visit_count_key(ip)).to_i
    end

    def reset_visit_count(ip)
      cache.delete(visit_count_key(ip))
    end

    def should_endless_stream?(ip)
      return false unless endless_stream_enabled?

      visit_count = get_visit_count(ip)

      return true if visit_count >= configuration.endless_stream_threshold

      rand(100) < configuration.endless_stream_random_chance
    end

    def calculate_tarpit_delay(visit_count)
      return 0 unless tarpit_enabled?

      base = configuration.tarpit_base_delay
      increment = configuration.tarpit_increment_per_visit
      max = configuration.tarpit_max_delay

      [base + (visit_count * increment), max].min
    end

    def notify_bot_trapped(data)
      log(:warn, "[PEST_CONTROL] 🍯 BOT TRAPPED: #{data.to_json}")
      configuration.on_bot_trapped&.call(data)

      if memory_enabled?
        TrapRecord.record_from_trap_data(data)
      end

      if sentry_enabled?
        Sentry.capture_message("[PEST_CONTROL] Bot trapped: #{data[:type]}", level: :warning, extra: data)
      end
    end

    def notify_endless_stream_start(ip, visit_count)
      log(:warn, "[PEST_CONTROL] 🌊 ENDLESS STREAM ACTIVATED: #{ip} (visit ##{visit_count})")
      configuration.on_endless_stream_start&.call(ip, visit_count)
    end

    def notify_bot_crashed(ip, chunks_sent, error)
      log(:warn, "[PEST_CONTROL] 💀 BOT CRASHED: #{ip} after #{chunks_sent} chunks (~#{chunks_sent}KB) - #{error.class}")
      configuration.on_bot_crashed&.call(ip, chunks_sent, error)
    end

    private

    def banned_ips_key
      "#{configuration.cache_key_prefix}:banned_ips"
    end

    def visit_count_key(ip)
      "#{configuration.cache_key_prefix}:visits:#{ip}"
    end
  end
end
