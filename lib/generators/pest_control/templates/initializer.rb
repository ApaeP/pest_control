# frozen_string_literal: true

# PestControl Configuration
# https://github.com/ApaeP/pest_control
#
# PestControl uses SAFE DEFAULTS out of the box:
#   - Endless stream: DISABLED (prevents thread exhaustion)
#   - Tarpit: enabled with conservative 10s max delay
#   - Credentials: hashed (passwords are SHA256 hashed before storage)
#   - Sensitive headers: automatically redacted
#
# See "CONFIGURATION PROFILES" at the bottom for pre-made configurations.

PestControl.configure do |config|
  # ============================================================================
  # BANNING
  # ============================================================================

  # How long IPs stay banned (default: 24 hours)
  # config.ban_duration = 24.hours

  # Set to false to disable banning (useful for testing)
  # config.banning_enabled = true

  # ============================================================================
  # DRY RUN MODE
  # ============================================================================
  # Enable this to test PestControl without actually banning IPs.
  # All actions are logged but no bans are applied.

  # config.dry_run = false

  # ============================================================================
  # CONCURRENCY LIMITS (anti self-DoS)
  # ============================================================================
  # Endless stream and tarpit block threads. These limits prevent attackers
  # from exhausting your worker pool by spamming requests.

  # Max concurrent endless streams (default: 5)
  # config.max_concurrent_streams = 5

  # Max concurrent tarpits (default: 10)
  # config.max_concurrent_tarpits = 10

  # What to do when limits are reached (default: :rickroll)
  # Options:
  #   :rickroll → Redirect to YouTube (instant, zero blocking)
  #   :block    → Instant 403 response (zero blocking)
  #   :tarpit   → Use tarpit if slots available, else rickroll
  #   "https://..." → Custom redirect URL
  # config.overflow_action = :rickroll

  # ============================================================================
  # ENDLESS STREAM
  # ============================================================================
  # Sends garbage data to waste bot resources. DISABLED BY DEFAULT for safety.
  # Enable only if you understand the thread-blocking implications.
  #
  # WARNING: Each active stream blocks a Puma worker thread!

  # Enable/disable endless stream (default: false)
  # config.endless_stream_enabled = false

  # Number of visits before activating endless stream (default: 5)
  # config.endless_stream_threshold = 5

  # Random chance of endless stream on any visit, 0-100 (default: 0%)
  # config.endless_stream_random_chance = 0

  # Max chunks to send, ~1KB each (default: 50_000 = ~50MB)
  # Increase for more aggressive streams (e.g., 500_000 = ~500MB)
  # config.max_stream_chunks = 50_000

  # Size of each garbage chunk in bytes (default: 1024)
  # config.stream_chunk_size = 1024

  # Delay between chunks in seconds (default: 0.1 to 0.5)
  # config.stream_chunk_delay_min = 0.1
  # config.stream_chunk_delay_max = 0.5

  # ============================================================================
  # TARPIT (progressive delays)
  # ============================================================================
  # Slows down responses to waste bot time. Protected by max_concurrent_tarpits.

  # Enable/disable tarpit (default: true)
  # config.tarpit_enabled = true

  # Base delay in seconds (default: 2)
  # config.tarpit_base_delay = 2

  # Maximum delay in seconds (default: 10)
  # config.tarpit_max_delay = 10

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

  # Enable Sentry integration (default: true, requires sentry-ruby gem)
  # config.sentry_enabled = true

  # Custom logger (default: Rails.logger)
  # config.logger = Rails.logger

  # Custom cache (default: Rails.cache)
  # For reliable IP banning, consider using Redis as your cache store.
  # config.cache = Rails.cache

  # ============================================================================
  # CALLBACKS
  # ============================================================================
  # Use Memory Mode (below) for built-in persistence, or these callbacks
  # for custom integrations.

  # Called when a bot is trapped (receives hash with all data)
  # config.on_bot_trapped = ->(data) {
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
  #   # Track success rate
  # }

  # ============================================================================
  # METRICS (Prometheus, StatsD, etc.)
  # ============================================================================
  # Called on every significant event for metrics collection.
  # Events: :trap, :ban, :ban_skipped, :unban, :stream_start, :stream_crash, :fingerprint

  # config.on_metrics = ->(data) {
  #   # data = { event: :trap, ip: "...", type: "...", timestamp: Time.current }
  #
  #   # Prometheus example:
  #   # PEST_CONTROL_EVENTS.labels(event: data[:event]).increment
  #
  #   # StatsD example:
  #   # StatsD.increment("pest_control.#{data[:event]}")
  # }

  # ============================================================================
  # CREDENTIAL CAPTURE & DATA HANDLING
  # ============================================================================
  # IMPORTANT: Credentials captured come from bots/attackers, but may contain
  # stolen data from third parties. Handle with care.

  # How to store captured credentials (default: :hash_password)
  # Options:
  #   :hash_password  → Hash passwords with SHA256, keep usernames in clear (RECOMMENDED)
  #   :username_only  → Only store usernames, no passwords at all
  #   :disabled       → Don't store any credentials
  #   :full           → Store everything in clear (use with extreme caution)
  # config.credentials_storage = :hash_password

  # Enable JavaScript fingerprinting on fake login page (default: true)
  # Collects: screen size, timezone, language, WebGL renderer, etc.
  # config.fingerprinting_enabled = true

  # ============================================================================
  # DATA REDACTION
  # ============================================================================
  # Headers that are NEVER logged, even if present in the request.
  # Add any custom headers that may contain sensitive data.

  # config.redacted_headers = %w[Cookie Authorization X-Api-Key X-Auth-Token X-CSRF-Token]

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
  # USER AGENTS
  # ============================================================================
  # Requires rack-attack gem for throttling to work.

  # Add custom user agents to throttle
  # config.suspicious_user_agents << /my-custom-bot/i

  # ============================================================================
  # MEMORY MODE (Database persistence & Dashboard)
  # ============================================================================
  # Enable this to persist bot attempts in your database and access the dashboard.
  # Run: rails generate pest_control:memory
  # Dashboard URL: /pest-control/lab

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

  # To clean up expired records, run periodically:
  #   rake pest_control:cleanup
  # Or in code:
  #   PestControl::TrapRecord.cleanup_expired!

  # ============================================================================
  # LEGACY REDIRECTS
  # ============================================================================
  # If your site was migrated from PHP/ASP/etc, you may have old backlinks
  # pointing to legacy URLs. Enable this to redirect them instead of banning.

  # Enable legacy URL handling (default: false)
  # config.legacy_redirects_enabled = false

  # File extensions to treat as legacy URLs (default: [])
  # config.legacy_extensions = %w[php xml asp aspx jsp]

  # Custom path mappings - takes priority over auto-strip (default: {})
  # config.legacy_mappings = {
  #   "/periode3.php" => "/periode-3",
  #   "/feed.xml"     => "/rss"
  # }

  # Auto-strip extension and redirect: /foo.php → /foo (default: true)
  # config.legacy_strip_extension = true

  # Number of allowed GET visits on unmapped legacy URLs before ban (default: 5)
  # POST/PUT/DELETE requests are always banned immediately
  # config.legacy_tolerance = 5

  # Log legacy redirect attempts as trap records (default: false)
  # config.legacy_log_redirects = false
end

# ============================================================================
# CONFIGURATION PROFILES
# ============================================================================
# Uncomment ONE of these profiles, or customize above.
#
# SAFE (default) - Conservative settings for production
# ---------------------------------------------------------
# PestControl.configure do |config|
#   config.endless_stream_enabled = false
#   config.tarpit_max_delay = 10
#   config.credentials_storage = :hash_password
# end
#
# MODERATE - Balanced security with some aggressive features
# ---------------------------------------------------------
# PestControl.configure do |config|
#   config.endless_stream_enabled = true
#   config.endless_stream_random_chance = 10
#   config.tarpit_max_delay = 20
#   config.credentials_storage = :hash_password
# end
#
# AGGRESSIVE - Maximum annoyance for bots (use with caution)
# ---------------------------------------------------------
# PestControl.configure do |config|
#   config.endless_stream_enabled = true
#   config.endless_stream_random_chance = 25
#   config.endless_stream_threshold = 3
#   config.max_stream_chunks = 200_000  # ~200MB
#   config.tarpit_max_delay = 30
#   config.credentials_storage = :full
# end
