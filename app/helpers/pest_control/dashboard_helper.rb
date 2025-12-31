# frozen_string_literal: true

module PestControl
  module DashboardHelper
    def stat_card(label:, value:, color:, path: nil, anchor: nil)
      href = anchor ? "##{anchor}" : path
      content_tag(:a, href: href, class: "stat-card") do
        content_tag(:div, label, class: "stat-label") +
          content_tag(:div, value, class: "stat-value #{color}")
      end
    end

    def trap_type_badge(record_or_type, linkable: false)
      type = record_or_type.respond_to?(:trap_type) ? record_or_type.trap_type : record_or_type.to_s
      badge_class = trap_type_to_badge_class(type)
      label = TrapRecord::TRAP_TYPE_LABELS[type] || type.to_s.titleize

      badge = content_tag(:span, label, class: "badge #{badge_class}")

      if linkable
        link_to badge, pest_control.pest_control_records_path(type: type), style: "text-decoration: none;"
      else
        badge
      end
    end

    def trap_type_to_badge_class(type)
      case type.to_s
      when "credential_capture", "credential_capture_blocked" then "badge-red"
      when "fake_login_view" then "badge-green"
      when "xmlrpc_attack" then "badge-yellow"
      when "fake_admin_access" then "badge-blue"
      else "badge-purple"
      end
    end

    def banned_badge(ip)
      return unless PestControl.banned?(ip)

      content_tag(:span, "🔒", class: "badge badge-red", title: "Banned")
    end

    def credentials_badge(record)
      if record.credentials.present?
        content_tag(:span, "🔑", class: "badge badge-yellow", title: "Has credentials")
      else
        content_tag(:span, "—", style: "color: var(--text-muted);")
      end
    end

    def ip_cell(ip, linkable: true)
      content_tag(:div, class: "ip-cell") do
        ip_content = if linkable
                       link_to(ip, pest_control.pest_control_records_path(ip: ip),
                               style: "color: inherit; text-decoration: none;")
                     else
                       ip
                     end
        safe_join([ip_content, banned_badge(ip)].compact)
      end
    end

    def pagination(page:, total_pages:, total_count:, per_page:)
      return if total_pages <= 1

      content_tag(:div, class: "pagination") do
        info = content_tag(:div, "Page #{page} of #{total_pages} (#{total_count} total)", class: "pagination-info")
        links = content_tag(:div, class: "pagination-links") do
          safe_join(pagination_links(page, total_pages))
        end
        info + links
      end
    end

    def filter_tag(label, value, param_to_remove)
      content_tag(:span, class: "filter-tag") do
        text = "#{label}: #{value}"
        remove_path = pest_control.pest_control_records_path(request.query_parameters.except(*Array(param_to_remove)))
        safe_join([text, " ", link_to("×", remove_path)])
      end
    end

    def filters_active?
      [:filter, :q, :type, :ip, :from, :to].any? { |p| params[p].present? }
    end

    def ban_toggle_button(ip, size: :normal)
      btn_class = size == :small ? "btn btn-sm" : "btn"

      if PestControl.banned?(ip)
        button_to "Unban", pest_control.pest_control_unban_path(ip: ip),
                  method: :post,
                  class: "#{btn_class} btn-success"
      else
        button_to "Ban", pest_control.pest_control_ban_path(ip: ip),
                  method: :post,
                  class: "#{btn_class} btn-danger"
      end
    end

    private

    def pagination_links(page, total_pages)
      links = []

      links << page_link(page - 1, "←", disabled: page <= 1)

      page_start = [1, page - 2].max
      page_end = [total_pages, page + 2].min

      if page_start > 1
        links << page_link(1, "1")
        links << page_link(nil, "...", disabled: true) if page_start > 2
      end

      (page_start..page_end).each do |p|
        links << page_link(p, p.to_s, active: p == page)
      end

      if page_end < total_pages
        links << page_link(nil, "...", disabled: true) if page_end < total_pages - 1
        links << page_link(total_pages, total_pages.to_s)
      end

      links << page_link(page + 1, "→", disabled: page >= total_pages)

      links
    end

    def page_link(page_num, label, active: false, disabled: false)
      css_class = ["page-link"]
      css_class << "active" if active
      css_class << "disabled" if disabled

      if disabled || page_num.nil?
        content_tag(:span, label, class: css_class.join(" "))
      else
        link_to label, pest_control.pest_control_records_path(request.query_parameters.merge(page: page_num)),
                class: css_class.join(" ")
      end
    end
  end
end
