# frozen_string_literal: true

module PestControl
  module LegacyHandler
    class << self
      def handle(request)
        return nil unless enabled?
        return nil unless legacy_extension?(request.path)
        return nil if wordpress_trap_path?(request.path)
        return :ban unless request.get?

        if (redirect_path = find_redirect_path(request.path))
          log_redirect(request, redirect_path) if config.legacy_log_redirects
          { action: :redirect, path: redirect_path }
        elsif within_tolerance?(request.remote_ip)
          log_tolerated(request) if config.legacy_log_redirects
          { action: :not_found }
        end
      end

      def enabled?
        config.legacy_redirects_enabled && config.legacy_extensions.any?
      end

      def legacy_extension?(path)
        extension = File.extname(path).delete_prefix(".").downcase
        config.legacy_extensions.map(&:downcase).include?(extension)
      end

      def wordpress_trap_path?(path)
        [
          %r{^/wp-login}i,
          %r{^/wp-admin}i,
          %r{^/wp-content}i,
          %r{^/wp-includes}i,
          %r{^/xmlrpc}i,
          %r{^/phpmyadmin}i,
          %r{^/phpMyAdmin}i,
        ].any? { |pattern| path.match?(pattern) }
      end

      def find_redirect_path(path)
        if config.legacy_mappings.key?(path)
          config.legacy_mappings[path]
        elsif config.legacy_strip_extension
          path.sub(/\.[^.]+\z/, "")
        end
      end

      def within_tolerance?(ip)
        visit_count = increment_legacy_visit_count(ip)
        visit_count <= config.legacy_tolerance
      end

      def increment_legacy_visit_count(ip)
        key = legacy_visit_count_key(ip)
        count = (PestControl.cache.read(key) || 0) + 1
        PestControl.cache.write(key, count, expires_in: config.visit_count_ttl)
        count
      end

      def get_legacy_visit_count(ip)
        PestControl.cache.read(legacy_visit_count_key(ip)).to_i
      end

      private

      def config
        PestControl.configuration
      end

      def legacy_visit_count_key(ip)
        "#{config.cache_key_prefix}:legacy_visits:#{ip}"
      end

      def log_redirect(request, redirect_path)
        data = build_log_data(request, "LEGACY_REDIRECT", redirect_path: redirect_path)
        record_trap(data)
      end

      def log_tolerated(request)
        visit_count = get_legacy_visit_count(request.remote_ip)
        data = build_log_data(request, "LEGACY_TOLERATED", visit_count: visit_count)
        record_trap(data)
      end

      def build_log_data(request, type, extra = {})
        {
          type: type,
          timestamp: Time.current.iso8601,
          ip: request.remote_ip,
          path: request.path,
          method: request.request_method,
          user_agent: request.user_agent,
          referer: request.referer,
          host: request.host,
        }.merge(extra)
      end

      def record_trap(data)
        PestControl.log(:info, "[PEST_CONTROL] 🔄 #{data[:type]}: #{data[:ip]} -> #{data[:path]}")

        return unless PestControl.memory_enabled?

        PestControl::TrapRecord.create(
          ip: data[:ip],
          trap_type: data[:type],
          path: data[:path],
          method: data[:method],
          user_agent: data[:user_agent],
          referer: data[:referer],
          host: data[:host],
          extra_data: data.except(:ip, :type, :path, :method, :user_agent, :referer, :host, :timestamp)
        )
      rescue ActiveRecord::ActiveRecordError => e
        PestControl.log(:error, "[PEST_CONTROL] Failed to save legacy trap record: #{e.message}")
      end
    end
  end
end
