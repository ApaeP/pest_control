# frozen_string_literal: true

module PestControl
  class DashboardController < ApplicationController
    before_action :authenticate!
    before_action :ensure_memory_enabled

    # GET /pest-control/lab
    def lab
      @stats = TrapRecord.stats
      @recent_records = TrapRecord.recent.limit(10)
      @top_ips = @stats[:top_ips]
      @by_type = @stats[:by_type]
      @banned_ips = PestControl.banned_ips

      # New stats for enhanced dashboard
      @daily_stats = TrapRecord.daily_stats(days: 7)
      @user_agent_stats = TrapRecord.user_agent_stats(limit: 10)
      @heatmap = TrapRecord.hourly_heatmap
      @trends = {
        today: TrapRecord.compare_period(period: :day),
        week: TrapRecord.compare_period(period: :week),
      }

      render layout: false
    end

    # GET /pest-control/lab/records
    def records
      @records = TrapRecord.recent

      case params[:filter]
      when "today"
        @records = @records.today
      when "credentials"
        @records = @records.with_credentials
      when "unique_ips"
        @records = @records.select("DISTINCT ON (ip) *").reorder("ip, created_at DESC") if postgres?
        @records = @records.group(:ip) unless postgres?
      end

      @records = @records.search(params[:q]) if params[:q].present?

      if params[:type].present?
        trap_type_value = TrapRecord.trap_types[params[:type]]
        @records = @records.by_type(trap_type_value) if trap_type_value
      end

      @records = @records.by_ip(params[:ip]) if params[:ip].present?

      if params[:from].present? || params[:to].present?
        from_date = params[:from].present? ? Date.parse(params[:from]) : 100.years.ago
        to_date = params[:to].present? ? Date.parse(params[:to]) : Date.current
        @records = @records.between_dates(from_date, to_date)
      end

      @total_count = @records.count

      @page = (params[:page] || 1).to_i
      @per_page = 50
      @total_pages = (@total_count.to_f / @per_page).ceil
      @records = @records.offset((@page - 1) * @per_page).limit(@per_page)

      @trap_types = TrapRecord.trap_types.keys

      render layout: false
    end

    # GET /pest-control/lab/record/:id
    def show
      @record = TrapRecord.find(params[:id])
      render layout: false
    end

    # POST /pest-control/lab/unban/:ip
    def unban
      ip = params[:ip]
      PestControl.unban_ip!(ip)
      redirect_to pest_control_lab_path, notice: "IP #{ip} has been unbanned!"
    end

    # POST /pest-control/lab/ban/:ip
    def ban
      ip = params[:ip]
      PestControl.ban_ip!(ip, "manual_ban_from_dashboard")
      redirect_to pest_control_lab_path, notice: "IP #{ip} has been banned!"
    end

    # GET /pest-control/lab/export.csv
    def export
      records = build_filtered_records

      respond_to do |format|
        format.csv do
          send_data records_to_csv(records),
                    filename: "pest_control_export_#{Date.current.iso8601}.csv",
                    type: "text/csv; charset=utf-8"
        end
      end
    end

    private

    def build_filtered_records
      records = TrapRecord.recent

      case params[:filter]
      when "today"
        records = records.today
      when "credentials"
        records = records.with_credentials
      end

      records = records.search(params[:q]) if params[:q].present?

      if params[:type].present?
        trap_type_value = TrapRecord.trap_types[params[:type]]
        records = records.by_type(trap_type_value) if trap_type_value
      end

      records = records.by_ip(params[:ip]) if params[:ip].present?

      if params[:from].present? || params[:to].present?
        from_date = params[:from].present? ? Date.parse(params[:from]) : 100.years.ago
        to_date = params[:to].present? ? Date.parse(params[:to]) : Date.current
        records = records.between_dates(from_date, to_date)
      end

      records
    end

    def records_to_csv(records)
      require "csv"

      CSV.generate(headers: true) do |csv|
        csv << ["id", "created_at", "ip", "trap_type", "path", "method", "user_agent", "referer", "visit_count", "has_credentials"]

        records.find_each do |record|
          csv << [
            record.id,
            record.created_at.iso8601,
            record.ip,
            record.trap_type,
            record.path,
            record.method,
            record.user_agent,
            record.referer,
            record.visit_count,
            record.credentials.present? ? "yes" : "no",
          ]
        end
      end
    end

    def postgres?
      ActiveRecord::Base.connection.adapter_name.downcase.include?("postgres")
    end

    def authenticate!
      if PestControl.configuration.dashboard_auth.present?
        unless PestControl.configuration.dashboard_auth.call(self)
          render plain: "🚫 Access Denied - You shall not pass!", status: :forbidden
        end
        return
      end

      username = PestControl.configuration.dashboard_username
      password = PestControl.configuration.dashboard_password

      if username.present? && password.present?
        authenticate_or_request_with_http_basic("Pest Control Lab") do |u, p|
          ActiveSupport::SecurityUtils.secure_compare(u, username) &&
            ActiveSupport::SecurityUtils.secure_compare(p, password)
        end
      elsif Rails.env.development?
        Rails.logger.warn "[PEST_CONTROL] ⚠️  Dashboard accessed without authentication configured!"
      else
        render plain: "🚫 Dashboard authentication not configured", status: :forbidden
      end
    end

    def ensure_memory_enabled
      return if PestControl.memory_enabled?

      render plain: "🧠 Memory Mode is not enabled. Run `rails generate pest_control:memory` first.",
             status: :service_unavailable
    end
  end
end
