# frozen_string_literal: true

module PestControl
  class Configuration
    # ===========================================================================
    # BANNING
    # ===========================================================================

    # How long IPs stay banned (default: 24 hours)
    attr_accessor :ban_duration

    # Whether to actually ban IPs (set to false for testing)
    attr_accessor :banning_enabled

    # ===========================================================================
    # ENDLESS STREAM
    # ===========================================================================

    # Enable/disable endless stream feature entirely
    attr_accessor :endless_stream_enabled

    # Number of visits before activating endless stream (default: 5)
    attr_accessor :endless_stream_threshold

    # Random chance of endless stream on any visit, 0-100 (default: 15%)
    attr_accessor :endless_stream_random_chance

    # Max number of chunks to send (~1KB each, default: 50_000 = ~50MB)
    attr_accessor :max_stream_chunks

    # Size of each garbage chunk in bytes (default: 1024)
    attr_accessor :stream_chunk_size

    # Delay range between chunks in seconds (default: 0.1..0.5)
    attr_accessor :stream_chunk_delay_min
    attr_accessor :stream_chunk_delay_max, :banned_ip_tarpit_max, :dashboard_password

    # Maximum concurrent endless streams to prevent self-DoS (default: 5)
    # When limit is reached, fallback action is used instead
    attr_accessor :max_concurrent_streams

    # What to do when max_concurrent_streams or max_concurrent_tarpits is reached
    # Options:
    #   - :rickroll → Redirect to YouTube rickroll (instant, zero blocking)
    #   - :block → Instant 403 response (zero blocking)
    #   - :tarpit → Use tarpit delay (only if tarpit slots available)
    #   - "https://..." → Custom redirect URL
    attr_accessor :overflow_action

    # ===========================================================================
    # TARPIT
    # ===========================================================================

    # Enable/disable tarpit feature entirely
    attr_accessor :tarpit_enabled

    # Base delay for tarpit in seconds (default: 2)
    attr_accessor :tarpit_base_delay

    # Max delay for tarpit in seconds (default: 30)
    attr_accessor :tarpit_max_delay

    # Delay increment per visit in seconds (default: 0.5)
    attr_accessor :tarpit_increment_per_visit

    # Tarpit delay range for banned IPs at Rack::Attack level (default: 5..10)
    attr_accessor :banned_ip_tarpit_min

    # Maximum concurrent tarpits to prevent self-DoS (default: 10)
    # When limit is reached, fallback action is used (same as stream_fallback)
    attr_accessor :max_concurrent_tarpits

    # ===========================================================================
    # VISIT TRACKING
    # ===========================================================================

    # TTL for visit counting per IP (default: 1 hour)
    attr_accessor :visit_count_ttl

    # Cache key prefix (default: "pest_control")
    attr_accessor :cache_key_prefix

    # ===========================================================================
    # LOGGING & CALLBACKS
    # ===========================================================================

    # Custom logger (defaults to Rails.logger)
    attr_accessor :logger

    # Custom cache (defaults to Rails.cache)
    attr_accessor :cache

    # Log level for honeypot events: :debug, :info, :warn, :error (default: :warn)
    attr_accessor :log_level

    # Enable Sentry integration (default: true)
    attr_accessor :sentry_enabled

    # Custom callback when a bot is trapped
    # Receives a hash with all trap data
    attr_accessor :on_bot_trapped

    # Custom callback when an IP is banned
    # Receives (ip, reason)
    attr_accessor :on_ip_banned

    # Custom callback when endless stream starts
    # Receives (ip, visit_count)
    attr_accessor :on_endless_stream_start

    # Custom callback when a bot crashes/disconnects during endless stream
    # Receives (ip, chunks_sent, error)
    attr_accessor :on_bot_crashed

    # ===========================================================================
    # CREDENTIAL CAPTURE
    # ===========================================================================

    # Enable/disable credential capture logging (default: true)
    attr_accessor :capture_credentials

    # Enable/disable JavaScript fingerprinting (default: true)
    attr_accessor :fingerprinting_enabled

    # ===========================================================================
    # FAKE PAGES CUSTOMIZATION
    # ===========================================================================

    # WordPress site name shown on fake login (default: "WordPress")
    attr_accessor :fake_site_name

    # Custom HTML for 403 blocked response (set to nil for default)
    attr_accessor :custom_blocked_html

    # Custom HTML for fake login page (set to nil for default)
    # If set, completely replaces the default fake_login.html.erb
    attr_accessor :custom_login_html

    # ===========================================================================
    # USER AGENTS
    # ===========================================================================

    # Suspicious user agents to throttle via Rack::Attack
    attr_accessor :suspicious_user_agents

    # ===========================================================================
    # DRY RUN MODE
    # ===========================================================================

    # Enable dry run mode: logs everything but doesn't ban IPs (default: false)
    # Useful for testing in production without affecting real users
    attr_accessor :dry_run

    # ===========================================================================
    # METRICS CALLBACKS
    # ===========================================================================

    # Called on every trap event with metrics data (for Prometheus/StatsD/etc)
    # Receives: { event: :trap|:ban|:stream|:redirect, ip:, type:, duration_ms: }
    attr_accessor :on_metrics

    # ===========================================================================
    # MEMORY MODE (Database persistence & Dashboard)
    # ===========================================================================

    # Enable/disable database persistence of trap records (default: false)
    # Requires running: rails generate pest_control:memory
    attr_accessor :memory_enabled

    # Dashboard authentication - HTTP Basic Auth credentials
    # If dashboard_auth lambda is set, these are ignored
    attr_accessor :dashboard_username

    # Dashboard authentication - Custom lambda (takes precedence over username/password)
    # Receives the controller instance, must return true/false
    # Example: ->(controller) { controller.current_user&.admin? }
    attr_accessor :dashboard_auth

    # How long to keep trap records in the database (default: 3 years)
    # Set to nil to keep records indefinitely
    attr_accessor :trap_records_retention

    # ===========================================================================
    # LEGACY REDIRECTS
    # ===========================================================================

    # Enable legacy URL handling for old sites migrated from PHP/ASP/etc (default: false)
    attr_accessor :legacy_redirects_enabled

    # File extensions to treat as legacy URLs (default: [])
    # Example: %w[php xml asp aspx jsp]
    attr_accessor :legacy_extensions

    # Custom path mappings, takes priority over auto-strip (default: {})
    # Example: { "/periode3.php" => "/periode-3", "/feed.xml" => "/rss" }
    attr_accessor :legacy_mappings

    # Auto-strip extension and redirect: /foo.php → /foo (default: true)
    attr_accessor :legacy_strip_extension

    # Number of allowed GET visits on unmapped legacy URLs before ban (default: 5)
    # POST/PUT/DELETE requests are banned immediately
    attr_accessor :legacy_tolerance

    # Log legacy redirect attempts as LEGACY_REDIRECT trap records (default: false)
    attr_accessor :legacy_log_redirects

    def initialize
      # Banning
      @ban_duration = 24.hours
      @banning_enabled = true

      # Endless stream
      @endless_stream_enabled = true
      @endless_stream_threshold = 5
      @endless_stream_random_chance = 15
      @max_stream_chunks = 50_000
      @stream_chunk_size = 1024
      @stream_chunk_delay_min = 0.1
      @stream_chunk_delay_max = 0.5
      @max_concurrent_streams = 5
      @overflow_action = :rickroll

      # Tarpit
      @tarpit_enabled = true
      @tarpit_base_delay = 2
      @tarpit_max_delay = 30
      @tarpit_increment_per_visit = 0.5
      @banned_ip_tarpit_min = 5
      @banned_ip_tarpit_max = 10
      @max_concurrent_tarpits = 10

      # Visit tracking
      @visit_count_ttl = 1.hour
      @cache_key_prefix = "pest_control"

      # Logging
      @logger = nil
      @cache = nil
      @log_level = :warn
      @sentry_enabled = true
      @on_bot_trapped = nil
      @on_ip_banned = nil
      @on_endless_stream_start = nil
      @on_bot_crashed = nil

      # Credential capture
      @capture_credentials = true
      @fingerprinting_enabled = true

      # Fake pages
      @fake_site_name = "WordPress"
      @custom_blocked_html = nil
      @custom_login_html = nil

      # User agents
      @suspicious_user_agents = default_suspicious_user_agents

      # Dry run & metrics
      @dry_run = false
      @on_metrics = nil

      # Memory mode
      @memory_enabled = false
      @dashboard_username = nil
      @dashboard_password = nil
      @dashboard_auth = nil
      @trap_records_retention = 3.years

      # Legacy redirects
      @legacy_redirects_enabled = false
      @legacy_extensions = []
      @legacy_mappings = {}
      @legacy_strip_extension = true
      @legacy_tolerance = 5
      @legacy_log_redirects = false
    end

    def stream_chunk_delay_range
      stream_chunk_delay_min..stream_chunk_delay_max
    end

    def banned_ip_tarpit_range
      banned_ip_tarpit_min..banned_ip_tarpit_max
    end

    def default_suspicious_user_agents
      [
        /zgrab/i,
        /masscan/i,
        /nmap/i,
        /nikto/i,
        /sqlmap/i,
        /dirbuster/i,
        /gobuster/i,
        /wpscan/i,
        /nuclei/i,
        /httpx/i,
        %r{curl/\d}i,
        /python-requests/i,
        /go-http-client/i,
        /libwww-perl/i,
        /wget/i,
        /scrapy/i,
        /bot(?!.*google|.*bing|.*yandex|.*duckduck)/i,
      ]
    end
  end
end
