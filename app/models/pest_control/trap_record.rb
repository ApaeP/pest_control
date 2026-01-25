# frozen_string_literal: true

module PestControl
  class TrapRecord < PestControl::ApplicationRecord
    self.table_name = "pest_control_trap_records"

    enum :trap_type, {
      fake_login_view: "FAKE_LOGIN_VIEW",
      credential_capture: "CREDENTIAL_CAPTURE",
      credential_capture_blocked: "CREDENTIAL_CAPTURE_BLOCKED",
      fake_admin_access: "FAKE_ADMIN_ACCESS",
      xmlrpc_attack: "XMLRPC_ATTACK",
      catch_all: "CATCH_ALL",
      legacy_redirect: "LEGACY_REDIRECT",
      legacy_tolerated: "LEGACY_TOLERATED",
    }, prefix: true

    validates :ip, presence: true
    validates :trap_type, presence: true

    scope :recent, -> { order(created_at: :desc) }
    scope :today, -> { where(created_at: Time.current.beginning_of_day..) }
    scope :yesterday, -> { where(created_at: 1.day.ago.all_day) }
    scope :by_ip, ->(ip) { where(ip: ip) }
    scope :by_type, ->(type) { where(trap_type: type) }
    scope :with_credentials, -> { where(trap_type: ["CREDENTIAL_CAPTURE", "CREDENTIAL_CAPTURE_BLOCKED"]) }

    scope :between_dates, ->(start_date, end_date) {
      where(created_at: start_date.beginning_of_day..end_date.end_of_day)
    }

    scope :search, ->(query) {
      return all if query.blank?

      sanitized = "%#{sanitize_sql_like(query)}%"
      like_operator = connection.adapter_name.downcase.include?("postgres") ? "ILIKE" : "LIKE"

      conditions = [
        "ip #{like_operator} :q",
        "path #{like_operator} :q",
        "user_agent #{like_operator} :q",
        "trap_type #{like_operator} :q",
      ].join(" OR ")
      where(conditions, q: sanitized)
    }

    scope :expired, -> {
      retention = PestControl.configuration.trap_records_retention
      return none if retention.nil?

      where(created_at: ...(Time.current - retention))
    }

    TRAP_TYPE_LABELS = {
      "fake_login_view" => "Fake Login View",
      "credential_capture" => "Credential Capture",
      "credential_capture_blocked" => "Credentials (Blocked IP)",
      "fake_admin_access" => "Fake Admin Access",
      "xmlrpc_attack" => "XML-RPC Attack",
      "catch_all" => "Catch-All",
      "legacy_redirect" => "Legacy Redirect",
      "legacy_tolerated" => "Legacy Tolerated",
    }.freeze

    class << self
      def record_from_trap_data(data)
        return unless PestControl.memory_enabled?

        create!(
          ip: data[:ip],
          trap_type: data[:type],
          path: data[:path],
          method: data[:method],
          user_agent: data[:user_agent],
          referer: data[:referer],
          host: data[:host],
          query_string: data[:query_string],
          headers: data[:headers],
          params: data[:params],
          credentials: data[:credentials],
          fingerprint: data[:fingerprint],
          visit_count: data[:visit_count],
          will_endless_stream: data[:will_endless_stream] || false,
          extra_data: data.except(
            :ip, :type, :path, :method, :user_agent, :referer, :host,
            :query_string, :headers, :params, :credentials, :fingerprint,
            :visit_count, :will_endless_stream, :timestamp
          )
        )
      rescue ActiveRecord::ActiveRecordError => e
        PestControl.log(:error, "[PEST_CONTROL] Failed to save TrapRecord: #{e.message}")
        nil
      end

      def stats
        {
          total: count,
          today: today.count,
          yesterday: yesterday.count,
          unique_ips: distinct.count(:ip),
          by_type: group(:trap_type).count,
          credentials_captured: with_credentials.count,
          top_ips: group(:ip).order(count_id: :desc).limit(10).count(:id),
        }
      end

      # Returns daily stats for the last N days
      # @param days [Integer] Number of days to include (default: 7)
      # @return [Array<Hash>] Array of {date:, count:, credentials:}
      def daily_stats(days: 7)
        start_date = (days - 1).days.ago.beginning_of_day
        end_date = Time.current.end_of_day

        # Get counts by date
        counts_by_date = where(created_at: start_date..end_date)
                         .group("DATE(created_at)")
                         .count

        credentials_by_date = with_credentials
                              .where(created_at: start_date..end_date)
                              .group("DATE(created_at)")
                              .count

        # Build array with all days (including zeros)
        (0...days).map do |i|
          date = (days - 1 - i).days.ago.to_date
          {
            date: date,
            count: counts_by_date[date] || 0,
            credentials: credentials_by_date[date] || 0,
          }
        end
      end

      # Returns top user agents by count
      # @param limit [Integer] Number of results (default: 10)
      # @return [Array<Hash>] Array of {user_agent:, count:, percentage:}
      def user_agent_stats(limit: 10)
        total = count
        return [] if total.zero?

        group(:user_agent)
          .order(count_id: :desc)
          .limit(limit)
          .count(:id)
          .map do |ua, ua_count|
            {
              user_agent: ua.presence || "(empty)",
              count: ua_count,
              percentage: (ua_count.to_f / total * 100).round(1),
            }
          end
      end

      # Returns activity heatmap by day of week and hour
      # @return [Hash] {day_of_week => {hour => count}}
      def hourly_heatmap
        # Get counts grouped by day of week (0-6) and hour (0-23)
        results = if connection.adapter_name.downcase.include?("postgres")
                    group("EXTRACT(DOW FROM created_at)::integer")
                      .group("EXTRACT(HOUR FROM created_at)::integer")
                      .count
                  else
                    group("CAST(strftime('%w', created_at) AS INTEGER)")
                      .group("CAST(strftime('%H', created_at) AS INTEGER)")
                      .count
                  end

        # Build 7x24 matrix with all zeros
        heatmap = (0..6).index_with { |_| (0..23).index_with { |_| 0 } }

        # Fill with actual counts
        results.each do |(dow, hour), heatmap_count|
          heatmap[dow.to_i][hour.to_i] = heatmap_count
        end

        heatmap
      end

      # Compares current period count to previous period
      # @param period [Symbol] :day, :week, or :month
      # @return [Hash] {current:, previous:, change:, percentage:}
      def compare_period(period: :day)
        case period
        when :day
          current_start = Time.current.beginning_of_day
          previous_start = 1.day.ago.beginning_of_day
          previous_end = 1.day.ago.end_of_day
        when :week
          current_start = Time.current.beginning_of_week
          previous_start = 1.week.ago.beginning_of_week
          previous_end = 1.week.ago.end_of_week
        when :month
          current_start = Time.current.beginning_of_month
          previous_start = 1.month.ago.beginning_of_month
          previous_end = 1.month.ago.end_of_month
        end

        current_count = where(created_at: current_start..).count
        previous_count = where(created_at: previous_start..previous_end).count

        change = current_count - previous_count
        percentage = previous_count.positive? ? ((change.to_f / previous_count) * 100).round(1) : nil

        {
          current: current_count,
          previous: previous_count,
          change: change,
          percentage: percentage,
        }
      end

      def cleanup_expired!
        retention = PestControl.configuration.trap_records_retention
        return 0 if retention.nil?

        deleted_count = expired.delete_all
        if deleted_count.positive?
          PestControl.log(:info,
                          "[PEST_CONTROL] 🧹 Cleaned up #{deleted_count} expired trap records")
        end
        deleted_count
      end
    end

    def trap_type_label
      TRAP_TYPE_LABELS[trap_type] || trap_type.to_s.titleize
    end

    def trap_type_badge_class
      case trap_type
      when "credential_capture", "credential_capture_blocked" then "badge-red"
      when "fake_login_view" then "badge-green"
      when "xmlrpc_attack" then "badge-yellow"
      when "fake_admin_access" then "badge-blue"
      when "legacy_redirect", "legacy_tolerated" then "badge-gray"
      else "badge-purple"
      end
    end
  end
end
