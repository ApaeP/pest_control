# frozen_string_literal: true

module PestControl
  class TrapsController < ApplicationController
    include ActionController::Live

    skip_before_action :verify_authenticity_token
    before_action :handle_legacy_redirect, except: [:capture_fingerprint]
    layout false

    TRANSPARENT_GIF = "\x47\x49\x46\x38\x39\x61\x01\x00\x01\x00\x80\x00\x00\xff\xff\xff\x00\x00\x00\x21\xf9\x04\x01\x00\x00\x00\x00\x2c\x00\x00\x00\x00\x01\x00\x01\x00\x00\x02\x02\x44\x01\x00\x3b".b.freeze

    # GET /wp-login.php
    def fake_login
      log_bot_attempt("FAKE_LOGIN_VIEW")

      if PestControl.should_endless_stream?(request.remote_ip)
        endless_stream_attack("fake_wordpress_page")
      else
        return unless apply_tarpit

        render_login_page
      end
    end

    # POST /wp-login.php
    def capture_credentials
      extra = {}

      if PestControl.capture_credentials?
        raw_credentials = {
          username: params[:log],
          password: params[:pwd],
          remember: params[:rememberme],
          redirect_to: params[:redirect_to],
        }
        extra[:credentials] = PestControl.sanitize_credentials(raw_credentials)
      end

      log_bot_attempt("CREDENTIAL_CAPTURE", extra)

      if PestControl.should_endless_stream?(request.remote_ip)
        endless_stream_attack("fake_wordpress_page")
      else
        return unless apply_tarpit(base_override: 5)

        @error = "ERROR: Invalid username or password."
        render_login_page
      end
    end

    # GET /wp-admin/*
    def fake_admin
      log_bot_attempt("FAKE_ADMIN_ACCESS")

      if PestControl.should_endless_stream?(request.remote_ip)
        endless_stream_attack("fake_admin_dashboard")
      else
        return unless apply_tarpit

        redirect_to "/wp-login.php?redirect_to=#{CGI.escape(request.path)}", allow_other_host: true
      end
    end

    # GET /*.php and other suspicious paths
    def catch_all
      log_bot_attempt("CATCH_ALL")

      if PestControl.should_endless_stream?(request.remote_ip)
        endless_stream_attack("fake_404")
      else
        return unless apply_tarpit(base_override: 1)

        render plain: fake_apache_404, status: :not_found, content_type: "text/html"
      end
    end

    # POST /xmlrpc.php
    def fake_xmlrpc
      body_content = begin
        request.body.read
      rescue StandardError
        ""
      end
      log_bot_attempt("XMLRPC_ATTACK", body: body_content.truncate(1000))

      if PestControl.should_endless_stream?(request.remote_ip)
        endless_stream_attack("fake_xml")
      else
        return unless apply_tarpit(base_override: 3)

        render xml: fake_xmlrpc_response, status: :ok
      end
    end

    # GET /wp-admin/fp.gif
    def capture_fingerprint
      return head :not_found unless PestControl.fingerprinting_enabled?

      if request.query_string.present?
        fingerprint_data = parse_fingerprint(request.query_string)
        store_fingerprint(request.remote_ip, fingerprint_data) if fingerprint_data
      end

      send_data TRANSPARENT_GIF, type: "image/gif", disposition: "inline"
    end

    private

    def parse_fingerprint(query_string)
      decoded = CGI.unescape(query_string)
      JSON.parse(decoded, symbolize_names: true)
    rescue JSON::ParserError
      nil
    end

    def store_fingerprint(ip, data)
      cache_key = "#{PestControl.configuration.cache_key_prefix}:fingerprint:#{ip}"
      PestControl.cache.write(cache_key, data, expires_in: 1.hour)

      PestControl.log(:debug, "[PEST_CONTROL] 🔍 Fingerprint captured: #{ip} - #{data}")
      PestControl.emit_metrics(event: :fingerprint, ip: ip, data: data)

      return unless PestControl.memory_enabled?

      recent_record = TrapRecord.where(ip: ip).where("created_at > ?", 5.minutes.ago).order(created_at: :desc).first
      recent_record&.update(fingerprint: data)
    end

    RICKROLL_URL = "https://www.youtube.com/watch?v=dQw4w9WgXcQ"

    def endless_stream_attack(type = "html")
      unless PestControl.acquire_stream_slot!
        handle_overflow
        return
      end

      visit_count = PestControl.increment_visit_count(request.remote_ip)
      PestControl.notify_endless_stream_start(request.remote_ip, visit_count)

      config = PestControl.configuration

      response.headers["Content-Type"] = content_type_for(type)
      response.headers["Cache-Control"] = "no-cache, no-store"
      response.headers["X-Accel-Buffering"] = "no"

      response.stream.write(stream_header(type))

      loop_count = 0
      max_loops = config.max_stream_chunks
      delay_range = config.stream_chunk_delay_range

      begin
        while loop_count < max_loops
          chunk = generate_garbage_chunk(type, loop_count, config.stream_chunk_size)
          response.stream.write(chunk)
          sleep(rand(delay_range))
          loop_count += 1

          if (loop_count % 100).zero?
            PestControl.log(:info,
                            "[PEST_CONTROL] 🌊 Streaming: #{request.remote_ip} - #{loop_count} chunks (~#{loop_count * config.stream_chunk_size / 1024}KB)")
          end
        end
      rescue ActionController::Live::ClientDisconnected, IOError => e
        PestControl.notify_bot_crashed(request.remote_ip, loop_count, e)
      ensure
        PestControl.release_stream_slot!
        response.stream.close
      end
    end

    def content_type_for(type)
      case type
      when "fake_xml" then "application/xml"
      when "fake_json" then "application/json"
      else "text/html"
      end
    end

    def stream_header(type)
      site_name = PestControl.configuration.fake_site_name

      case type
      when "fake_wordpress_page"
        <<~HTML
          <!DOCTYPE html>
          <html lang="en-US">
          <head><meta charset="UTF-8"><title>#{site_name} Dashboard</title></head>
          <body><h1>Loading #{site_name}...</h1><div id="content">
        HTML
      when "fake_admin_dashboard"
        <<~HTML
          <!DOCTYPE html>
          <html><head><title>Dashboard ‹ #{site_name}</title></head>
          <body class="wp-admin"><div id="wpwrap"><h1>Welcome to #{site_name}</h1>
        HTML
      when "fake_404"
        <<~HTML
          <!DOCTYPE HTML><html><head><title>Processing...</title></head>
          <body><h1>Please wait...</h1><div class="content">
        HTML
      when "fake_xml"
        '<?xml version="1.0" encoding="UTF-8"?><response><status>processing</status><data>'
      else
        "<html><body><div>"
      end
    end

    def generate_garbage_chunk(type, iteration, target_size)
      words = ["wordpress", "plugin", "theme", "update", "security", "cache", "optimize", "database", "query",
               "result", "loading", "processing", "content", "media", "attachment", "thumbnail", "gallery", "slider", "widget", "sidebar", "menu", "navigation", "header", "footer", "template",]

      case type
      when "fake_xml"
        items = []
        while items.join.bytesize < target_size
          items << "<item id=\"#{(iteration * 20) + items.size}\"><value>#{words.sample(5).join(" ")}</value><data>#{SecureRandom.hex(32)}</data></item>\n"
        end
        items.join
      else
        chunks = []
        while chunks.join.bytesize < target_size
          chunks << <<~HTML
            <div class="wp-block-#{words.sample}" data-id="#{SecureRandom.hex(8)}">
              <span>#{words.sample(4).join(" ")}</span>
              <input type="hidden" value="#{SecureRandom.hex(16)}">
            </div>
          HTML
        end
        "<!-- chunk #{iteration} -->\n" + chunks.join
      end
    end

    def apply_tarpit(base_override: nil)
      return true unless PestControl.tarpit_enabled?

      unless PestControl.acquire_tarpit_slot!
        handle_overflow
        return false
      end

      visit_count = PestControl.increment_visit_count(request.remote_ip)

      if base_override
        config = PestControl.configuration
        delay = [base_override + (visit_count * config.tarpit_increment_per_visit), config.tarpit_max_delay].min
      else
        delay = PestControl.calculate_tarpit_delay(visit_count)
      end

      PestControl.log(:info,
                      "[PEST_CONTROL] ⏳ Tarpit: #{request.remote_ip} - visit ##{visit_count} - #{delay.round(1)}s delay")
      begin
        sleep(delay)
      ensure
        PestControl.release_tarpit_slot!
      end
      true
    end

    def render_login_page
      custom_html = PestControl.configuration.custom_login_html

      if custom_html
        render html: custom_html.html_safe, content_type: "text/html"
      else
        render :fake_login, content_type: "text/html"
      end
    end

    def log_bot_attempt(type, extra = {})
      visit_count = PestControl.get_visit_count(request.remote_ip) + 1

      data = {
        type: type,
        visit_count: visit_count,
        timestamp: Time.current.iso8601,
        ip: request.remote_ip,
        path: request.path,
        method: request.request_method,
        user_agent: request.user_agent,
        referer: request.referer,
        host: request.host,
        query_string: request.query_string,
        params: filtered_params,
        headers: extract_headers,
        will_endless_stream: PestControl.should_endless_stream?(request.remote_ip),
      }.merge(extra)

      PestControl.notify_bot_trapped(data)
      PestControl.ban_ip!(request.remote_ip, "honeypot:#{type}") unless PestControl.banned?(request.remote_ip)
    end

    def filtered_params
      raw = request.params.except(:controller, :action, :path)
      raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
    end

    def extract_headers
      headers_to_capture = [
        "X-Forwarded-For", "X-Real-IP", "CF-Connecting-IP", "Via",
        "Accept-Language", "Accept-Encoding", "Accept",
      ]

      redacted = PestControl.configuration.redacted_headers.map(&:downcase)

      headers_to_capture.each_with_object({}) do |header, hash|
        next if redacted.include?(header.downcase)

        key = "HTTP_#{header.upcase.tr("-", "_")}"
        value = request.headers[key]
        hash[header] = value if value.present?
      end
    end

    def fake_apache_404
      <<~HTML
        <!DOCTYPE HTML PUBLIC "-//IETF//DTD HTML 2.0//EN">
        <html><head><title>404 Not Found</title></head><body>
        <h1>Not Found</h1>
        <p>The requested URL #{ERB::Util.html_escape(request.path)} was not found on this server.</p>
        <hr><address>Apache/2.4.52 (Ubuntu) Server at #{request.host} Port 80</address>
        </body></html>
      HTML
    end

    def fake_xmlrpc_response
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <methodResponse>
          <fault><value><struct>
            <member><name>faultCode</name><value><int>403</int></value></member>
            <member><name>faultString</name><value><string>XML-RPC services are disabled.</string></value></member>
          </struct></value></fault>
        </methodResponse>
      XML
    end

    def handle_legacy_redirect
      result = PestControl::LegacyHandler.handle(request)
      return if result.nil? || result == :ban

      case result[:action]
      when :redirect
        redirect_to result[:path], status: :moved_permanently, allow_other_host: false
      when :not_found
        render plain: fake_apache_404, status: :not_found, content_type: "text/html"
      end
    end

    def handle_overflow
      action = PestControl.configuration.overflow_action

      case action
      when :rickroll
        PestControl.log(:info, "[PEST_CONTROL] 🎵 Rickrolling bot: #{request.remote_ip}")
        redirect_to RICKROLL_URL, allow_other_host: true
      when :block
        PestControl.log(:info, "[PEST_CONTROL] 🚫 Blocking bot: #{request.remote_ip}")
        render plain: "403 Forbidden", status: :forbidden
      when :tarpit
        if PestControl.acquire_tarpit_slot!
          PestControl.log(:info, "[PEST_CONTROL] ⏳ Tarpitting bot: #{request.remote_ip}")
          begin
            sleep(10)
          ensure
            PestControl.release_tarpit_slot!
          end
          render plain: fake_apache_404, status: :not_found, content_type: "text/html"
        else
          PestControl.log(:info, "[PEST_CONTROL] 🎵 Tarpit full, rickrolling: #{request.remote_ip}")
          redirect_to RICKROLL_URL, allow_other_host: true
        end
      when String
        PestControl.log(:info, "[PEST_CONTROL] ↗️ Redirecting bot to #{action}: #{request.remote_ip}")
        redirect_to action, allow_other_host: true
      else
        redirect_to RICKROLL_URL, allow_other_host: true
      end
    end
  end
end
