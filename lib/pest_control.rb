# frozen_string_literal: true

require "digest"
require "pest_control/version"
require "pest_control/configuration"
require "pest_control/engine"
require "pest_control/rack_attack_rules"
require "pest_control/legacy_handler"

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
      configuration.banning_enabled && !dry_run?
    end

    def dry_run?
      configuration.dry_run
    end

    def endless_stream_enabled?
      configuration.endless_stream_enabled
    end

    def tarpit_enabled?
      configuration.tarpit_enabled
    end

    def capture_credentials?
      configuration.credentials_storage != :disabled
    end

    def credentials_storage_mode
      configuration.credentials_storage
    end

    def fingerprinting_enabled?
      configuration.fingerprinting_enabled
    end

    def sanitize_credentials(credentials)
      return nil if credentials.blank?

      mode = credentials_storage_mode

      case mode
      when :disabled
        nil
      when :username_only
        {
          username: credentials[:username],
          captured_at: Time.current.iso8601,
        }.compact
      when :full
        credentials.merge(captured_at: Time.current.iso8601)
      else
        {
          username: credentials[:username],
          password_hash: credentials[:password].present? ? Digest::SHA256.hexdigest(credentials[:password].to_s) : nil,
          remember: credentials[:remember],
          redirect_to: credentials[:redirect_to],
          raw_params: credentials[:raw_params],
          captured_at: Time.current.iso8601,
        }.compact
      end
    end

    def memory_enabled?
      configuration.memory_enabled
    end

    def ban_ip!(ip, reason = "wordpress_scan")
      if dry_run?
        log(:info, "[PEST_CONTROL] 🧪 DRY RUN - Would ban IP: #{ip} - Reason: #{reason}")
        emit_metrics(event: :ban_skipped, ip: ip, reason: reason)
        return
      end

      return unless configuration.banning_enabled

      ban_data = {
        banned_at: Time.current.iso8601,
        reason: reason,
        expires_at: (Time.current + configuration.ban_duration).iso8601,
      }

      cache.write(ban_key(ip), ban_data, expires_in: configuration.ban_duration)
      add_to_ban_index(ip)

      log(:warn, "[PEST_CONTROL] 🔨 IP BANNED: #{ip} - Reason: #{reason}")
      emit_metrics(event: :ban, ip: ip, reason: reason)

      configuration.on_ip_banned&.call(ip, reason)
    end

    def banned?(ip)
      return false unless configuration.banning_enabled
      return false if dry_run?

      ban_data = cache.read(ban_key(ip))
      return false unless ban_data

      expires_at = Time.zone.parse(ban_data[:expires_at])
      if expires_at < Time.current
        cache.delete(ban_key(ip))
        false
      else
        true
      end
    end

    def banned_ips
      index = cache.read(ban_index_key) || []
      result = {}

      index.each do |ip|
        ban_data = cache.read(ban_key(ip))
        result[ip] = ban_data if ban_data && Time.zone.parse(ban_data[:expires_at]) > Time.current
      end

      cleanup_ban_index(result.keys) if result.size < index.size
      result
    end

    def unban_ip!(ip)
      cache.delete(ban_key(ip))
      remove_from_ban_index(ip)
      log(:info, "[PEST_CONTROL] ✅ IP unbanned: #{ip}")
      emit_metrics(event: :unban, ip: ip)
    end

    def clear_all_bans!
      banned_ips.each_key { |ip| cache.delete(ban_key(ip)) }
      cache.delete(ban_index_key)
      log(:info, "[PEST_CONTROL] ✅ All bans cleared")
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
      return false if max_streams_reached?

      visit_count = get_visit_count(ip)

      return true if visit_count >= configuration.endless_stream_threshold

      rand(100) < configuration.endless_stream_random_chance
    end

    def max_streams_reached?
      current = active_streams_count
      max = configuration.max_concurrent_streams
      if current >= max
        log(:info, "[PEST_CONTROL] ⚠️ Max concurrent streams reached (#{current}/#{max}), using tarpit instead")
        true
      else
        false
      end
    end

    def active_streams_count
      cache.read(active_streams_key).to_i
    end

    def acquire_stream_slot!
      count = active_streams_count
      max = configuration.max_concurrent_streams
      return false if count >= max

      cache.write(active_streams_key, count + 1, expires_in: 1.hour)
      true
    end

    def release_stream_slot!
      count = active_streams_count
      new_count = [count - 1, 0].max
      cache.write(active_streams_key, new_count, expires_in: 1.hour)
    end

    def active_tarpits_count
      cache.read(active_tarpits_key).to_i
    end

    def acquire_tarpit_slot!
      count = active_tarpits_count
      max = configuration.max_concurrent_tarpits
      return false if count >= max

      cache.write(active_tarpits_key, count + 1, expires_in: 1.minute)
      true
    end

    def release_tarpit_slot!
      count = active_tarpits_count
      new_count = [count - 1, 0].max
      cache.write(active_tarpits_key, new_count, expires_in: 1.minute)
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
      emit_metrics(event: :trap, ip: data[:ip], type: data[:type])

      TrapRecord.record_from_trap_data(data) if memory_enabled?

      return unless sentry_enabled?

      Sentry.capture_message("[PEST_CONTROL] Bot trapped: #{data[:type]}", level: :warning, extra: data)
    end

    def notify_endless_stream_start(ip, visit_count)
      log(:warn, "[PEST_CONTROL] 🌊 ENDLESS STREAM ACTIVATED: #{ip} (visit ##{visit_count})")
      configuration.on_endless_stream_start&.call(ip, visit_count)
      emit_metrics(event: :stream_start, ip: ip, visit_count: visit_count)
    end

    def notify_bot_crashed(ip, chunks_sent, error)
      log(:warn, "[PEST_CONTROL] 💀 BOT CRASHED: #{ip} after #{chunks_sent} chunks (~#{chunks_sent}KB) - #{error.class}")
      configuration.on_bot_crashed&.call(ip, chunks_sent, error)
      emit_metrics(event: :stream_crash, ip: ip, chunks_sent: chunks_sent)
    end

    def emit_metrics(data)
      configuration.on_metrics&.call(data.merge(timestamp: Time.current))
    end

    private

    def ban_key(ip)
      "#{configuration.cache_key_prefix}:ban:#{ip}"
    end

    def ban_index_key
      "#{configuration.cache_key_prefix}:ban_index"
    end

    def add_to_ban_index(ip)
      index = cache.read(ban_index_key) || []
      return if index.include?(ip)

      index << ip
      cache.write(ban_index_key, index)
    end

    def remove_from_ban_index(ip)
      index = cache.read(ban_index_key) || []
      index.delete(ip)
      cache.write(ban_index_key, index)
    end

    def cleanup_ban_index(active_ips)
      cache.write(ban_index_key, active_ips)
    end

    def visit_count_key(ip)
      "#{configuration.cache_key_prefix}:visits:#{ip}"
    end

    def active_streams_key
      "#{configuration.cache_key_prefix}:active_streams"
    end

    def active_tarpits_key
      "#{configuration.cache_key_prefix}:active_tarpits"
    end
  end
end
