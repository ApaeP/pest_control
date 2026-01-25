# frozen_string_literal: true

# rubocop:disable Metrics/BlockLength
namespace :pest_control do
  desc "List all routes captured by PestControl honeypots"
  task routes: :environment do
    puts ""
    puts "PestControl Routes"
    puts "=" * 60
    puts ""
    puts "The engine is mounted at \"/\" to intercept requests at the root level."
    puts "This is required to catch paths like /wp-login.php."
    puts ""
    puts "Dashboard Routes (requires Memory Mode):"
    puts "-" * 60
    puts "  GET    /pest-control/lab              Dashboard home"
    puts "  GET    /pest-control/lab/records      Records list (paginated)"
    puts "  GET    /pest-control/lab/record/:id   Record detail"
    puts "  POST   /pest-control/lab/ban/:ip      Ban an IP"
    puts "  POST   /pest-control/lab/unban/:ip    Unban an IP"
    puts ""
    puts "Honeypot Traps:"
    puts "-" * 60
    puts "  GET    /wp-login.php                  Fake WordPress login page"
    puts "  POST   /wp-login.php                  Capture login credentials"
    puts "  GET    /wp-login                      Fake WordPress login (alt)"
    puts "  *      /xmlrpc.php                    Fake XML-RPC endpoint"
    puts "  GET    /wp-admin/fp.gif               Fingerprint capture pixel"
    puts "  GET    /wp-admin/*                    Fake admin area"
    puts "  GET    /wp-content/*                  WordPress content trap"
    puts "  GET    /wp-includes/*                 WordPress includes trap"
    puts "  GET    /wp-json/*                     WordPress REST API trap"
    puts "  GET    /phpmyadmin*                   phpMyAdmin trap"
    puts "  GET    /administrator*                Admin panel trap"
    puts "  GET    /.env                          Environment file trap"
    puts "  GET    /.git/*                        Git repository trap"
    puts "  *      *.php                          Any PHP file (catch-all)"
    puts ""
    puts "Legacy URL Handling:"
    puts "-" * 60
    if PestControl.configuration.legacy_redirects_enabled
      extensions = PestControl.configuration.legacy_extensions
      if extensions.any?
        puts "  Enabled for extensions: #{extensions.join(", ")}"
        puts "  Tolerance: #{PestControl.configuration.legacy_tolerance} visits before ban"
        if PestControl.configuration.legacy_mappings.any?
          puts "  Custom mappings:"
          PestControl.configuration.legacy_mappings.each do |from, to|
            puts "    #{from} -> #{to}"
          end
        end
      else
        puts "  Enabled but no extensions configured"
      end
    else
      puts "  Disabled (enable with config.legacy_redirects_enabled = true)"
    end
    puts ""
    puts "Current Configuration:"
    puts "-" * 60
    config = PestControl.configuration
    puts "  Banning enabled:      #{config.banning_enabled}"
    puts "  Ban duration:         #{config.ban_duration.inspect}"
    puts "  Tarpit enabled:       #{config.tarpit_enabled}"
    puts "  Tarpit max delay:     #{config.tarpit_max_delay}s"
    puts "  Endless stream:       #{config.endless_stream_enabled}"
    puts "  Credentials storage:  #{config.credentials_storage}"
    puts "  Memory mode:          #{config.memory_enabled}"
    puts "  Dry run:              #{config.dry_run}"
    puts ""
    puts "Note: Your application routes take precedence over PestControl."
    puts "If you have a route like '/wp-login.php', PestControl won't intercept it."
    puts ""
  end

  desc "Show current PestControl configuration"
  task config: :environment do
    config = PestControl.configuration

    puts ""
    puts "PestControl Configuration"
    puts "=" * 60
    puts ""

    puts "Banning:"
    puts "  ban_duration:              #{config.ban_duration.inspect}"
    puts "  banning_enabled:           #{config.banning_enabled}"
    puts "  dry_run:                   #{config.dry_run}"
    puts ""

    puts "Endless Stream:"
    puts "  endless_stream_enabled:    #{config.endless_stream_enabled}"
    puts "  endless_stream_threshold:  #{config.endless_stream_threshold}"
    puts "  endless_stream_random_chance: #{config.endless_stream_random_chance}%"
    puts "  max_concurrent_streams:    #{config.max_concurrent_streams}"
    stream_mb = config.max_stream_chunks * config.stream_chunk_size / 1024 / 1024
    puts "  max_stream_chunks:         #{config.max_stream_chunks} (~#{stream_mb}MB)"
    puts "  overflow_action:           #{config.overflow_action.inspect}"
    puts ""

    puts "Tarpit:"
    puts "  tarpit_enabled:            #{config.tarpit_enabled}"
    puts "  tarpit_base_delay:         #{config.tarpit_base_delay}s"
    puts "  tarpit_max_delay:          #{config.tarpit_max_delay}s"
    puts "  tarpit_increment_per_visit: #{config.tarpit_increment_per_visit}s"
    puts "  max_concurrent_tarpits:    #{config.max_concurrent_tarpits}"
    puts ""

    puts "Credentials & Fingerprinting:"
    puts "  credentials_storage:       #{config.credentials_storage}"
    puts "  fingerprinting_enabled:    #{config.fingerprinting_enabled}"
    puts ""

    puts "Data Redaction:"
    puts "  redacted_headers:          #{config.redacted_headers.join(", ")}"
    puts ""

    puts "Memory Mode:"
    puts "  memory_enabled:            #{config.memory_enabled}"
    puts "  trap_records_retention:    #{config.trap_records_retention&.inspect || "forever"}"
    puts ""

    puts "Integrations:"
    puts "  sentry_enabled:            #{config.sentry_enabled}"
    rack_status = defined?(Rack::Attack) ? "yes" : "NO (IP blocking disabled)"
    puts "  rack-attack installed:     #{rack_status}"
    puts ""
  end

  desc "Show banned IPs"
  task banned: :environment do
    banned = PestControl.banned_ips

    puts ""
    puts "PestControl Banned IPs"
    puts "=" * 60

    if banned.empty?
      puts "No IPs currently banned."
    else
      puts ""
      puts "  IP                   Banned At                 Expires At"
      puts "  #{"-" * 56}"
      banned.each do |ip, data|
        puts "  #{ip.ljust(20)} #{data[:banned_at].to_s.ljust(25)} #{data[:expires_at]}"
      end
    end
    puts ""
  end

  desc "Clear all bans"
  task clear_bans: :environment do
    count = PestControl.banned_ips.size
    PestControl.clear_all_bans!
    puts "Cleared #{count} banned IP(s)."
  end

  desc "Clean up expired trap records (Memory Mode)"
  task cleanup: :environment do
    unless PestControl.memory_enabled?
      puts "Memory Mode is not enabled. Nothing to clean up."
      exit
    end

    deleted = PestControl::TrapRecord.cleanup_expired!
    puts "Deleted #{deleted} expired trap record(s)."
  end
end
# rubocop:enable Metrics/BlockLength
