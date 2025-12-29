# frozen_string_literal: true

# PestControl Configuration
# https://github.com/ApaeP/pest_control
#
# All options have sensible defaults. Uncomment and modify as needed.

PestControl.configure do |config|
  # ============================================================================
  # BANNING
  # ============================================================================

  # How long IPs stay banned (default: 24 hours)
  # config.ban_duration = 24.hours

  # Set to false to disable banning (useful for testing)
  # config.banning_enabled = true

  # ============================================================================
  # ENDLESS STREAM (the kill shot)
  # ============================================================================

  # Enable/disable endless stream feature (default: true)
  # config.endless_stream_enabled = true

  # Number of visits before activating endless stream (default: 5)
  # config.endless_stream_threshold = 5

  # Random chance of endless stream on any visit, 0-100 (default: 15%)
  # config.endless_stream_random_chance = 15

  # Max chunks to send, ~1KB each (default: 50_000 = ~50MB)
  # config.max_stream_chunks = 50_000

  # Size of each garbage chunk in bytes (default: 1024)
  # config.stream_chunk_size = 1024

  # Delay between chunks in seconds (default: 0.1 to 0.5)
  # config.stream_chunk_delay_min = 0.1
  # config.stream_chunk_delay_max = 0.5

  # ============================================================================
  # TARPIT (progressive delays)
  # ============================================================================

  # Enable/disable tarpit feature (default: true)
  # config.tarpit_enabled = true

  # Base delay in seconds (default: 2)
  # config.tarpit_base_delay = 2

  # Maximum delay in seconds (default: 30)
  # config.tarpit_max_delay = 30

  # Additional delay per visit in seconds (default: 0.5)
  # config.tarpit_increment_per_visit = 0.5

  # Tarpit delay range for banned IPs at Rack::Attack level (default: 5 to 10)
  # config.banned_ip_tarpit_min = 5
  # config.banned_ip_tarpit_max = 10

  # ============================================================================
  # VISIT TRACKING
  # ============================================================================

  # How long to remember visits per IP (default: 1 hour)
  # config.visit_count_ttl = 1.hour

  # Cache key prefix (default: "pest_control")
  # config.cache_key_prefix = "pest_control"

  # ============================================================================
  # LOGGING & MONITORING
  # ============================================================================

  # Log level: :debug, :info, :warn, :error (default: :warn)
  # config.log_level = :warn

  # Enable Sentry integration (default: true)
  # config.sentry_enabled = true

  # Custom logger (default: Rails.logger)
  # config.logger = Rails.logger

  # Custom cache (default: Rails.cache)
  # config.cache = Rails.cache

  # ============================================================================
  # CALLBACKS
  # ============================================================================

  # Called when a bot is trapped (receives hash with all data)
  # config.on_bot_trapped = ->(data) {
  #   # Save to database
  #   # BotAttempt.create!(data)
  #
  #   # Send to Slack
  #   # SlackNotifier.notify("#security", "Bot trapped: #{data[:ip]}")
  # }

  # Called when an IP is banned (receives ip, reason)
  # config.on_ip_banned = ->(ip, reason) {
  #   # Add to external blocklist
  #   # Firewall.block_ip(ip)
  # }

  # Called when endless stream starts (receives ip, visit_count)
  # config.on_endless_stream_start = ->(ip, visit_count) {
  #   # Log to monitoring
  # }

  # Called when a bot crashes during endless stream (receives ip, chunks_sent, error)
  # config.on_bot_crashed = ->(ip, chunks_sent, error) {
  #   # Celebrate! 🎉
  # }

  # ============================================================================
  # CREDENTIAL CAPTURE
  # ============================================================================

  # Log captured credentials (default: true)
  # config.capture_credentials = true

  # Enable JavaScript fingerprinting (default: true)
  # config.fingerprinting_enabled = true

  # ============================================================================
  # FAKE PAGES
  # ============================================================================

  # WordPress site name shown on fake login (default: "WordPress")
  # config.fake_site_name = "WordPress"

  # Custom HTML for 403 blocked response (default: nil = use built-in)
  # config.custom_blocked_html = "<html><body><h1>Blocked</h1></body></html>"

  # Custom HTML for fake login page (default: nil = use built-in)
  # config.custom_login_html = nil

  # ============================================================================
  # PATTERNS
  # ============================================================================

  # Add custom patterns to catch
  # config.blocked_patterns << /\/my-custom-path/i

  # Add custom user agents to throttle
  # config.suspicious_user_agents << /my-custom-bot/i

  # ============================================================================
  # MEMORY MODE (Database persistence & Dashboard)
  # ============================================================================
  # Enable this to persist bot attempts in your database and access the dashboard.
  # Run: rails generate pest_control:memory

  # Enable database persistence (default: false)
  # config.memory_enabled = false

  # Dashboard authentication - Option 1: HTTP Basic Auth
  # config.dashboard_username = "admin"
  # config.dashboard_password = ENV["PEST_CONTROL_DASHBOARD_PASSWORD"]

  # Dashboard authentication - Option 2: Custom lambda (takes precedence)
  # Example: only allow admin users
  # config.dashboard_auth = ->(controller) { controller.current_user&.admin? }

  # How long to keep trap records in the database (default: 3 years)
  # Set to nil to keep records indefinitely
  # config.trap_records_retention = 3.years

  # To clean up expired records, run periodically (e.g., via a cron job):
  #   PestControl::TrapRecord.cleanup_expired!
end
