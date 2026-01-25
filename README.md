# PestControl

[![CI](https://github.com/ApaeP/pest_control/actions/workflows/ci.yml/badge.svg)](https://github.com/ApaeP/pest_control/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/ApaeP/pest_control/graph/badge.svg)](https://codecov.io/gh/ApaeP/pest_control)
[![Ruby](https://img.shields.io/badge/ruby-3.4-CC342D.svg?logo=ruby)](https://www.ruby-lang.org/)
[![Rails](https://img.shields.io/badge/rails-8.1-D30001.svg?logo=rubyonrails)](https://rubyonrails.org/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](MIT-LICENSE)

A production-ready Rails gem to trap, analyze, and neutralize bots scanning your site for vulnerabilities.

## Threat Model

### What PestControl Targets

- **Automated vulnerability scanners** looking for WordPress, PHP, and common CMS paths
- **Credential stuffing bots** attempting login on `/wp-login.php`, `/xmlrpc.php`
- **Script kiddies** probing for `.env`, `.git`, phpMyAdmin, and admin panels
- **Reconnaissance tools** like zgrab, masscan, nikto, wpscan

### What PestControl Does NOT Target

- Legitimate crawlers (Googlebot, Bingbot are whitelisted by default)
- Normal 404s from broken links (use Legacy Redirects for that)
- DDoS attacks (use a CDN/WAF for that)
- Application-level attacks (use proper authentication and input validation)

### Defense Strategy

1. **Detect**: Honeypot routes catch requests to paths that should never exist on a Rails app
2. **Delay**: Progressive tarpit wastes attacker time (2-10s delay per request)
3. **Ban**: IP is banned after first trap (24h by default)
4. **Analyze**: Optional database persistence for threat intelligence

## Quick Start

```bash
# Add to Gemfile
gem "pest_control", github: "ApaeP/pest_control"
gem "rack-attack"  # Recommended for IP blocking at Rack level

# Install
bundle install
rails generate pest_control:install

# Done! Bots hitting /wp-login.php will now be trapped.
```

## Safe Defaults

PestControl ships with **conservative defaults** suitable for production:

| Feature | Default | Why |
|---------|---------|-----|
| Endless stream | **Disabled** | Blocks Puma threads, can cause self-DoS |
| Random stream chance | **0%** | No surprise resource consumption |
| Max tarpit delay | **10s** | Reasonable delay without blocking too long |
| Credentials storage | **:hash_password** | Passwords are SHA256 hashed, never stored in clear |
| Sensitive headers | **Redacted** | Cookie, Authorization, API keys never logged |

To enable more aggressive features, see [Configuration Profiles](#configuration-profiles).

## Decision Flow

```
Request arrives (e.g., GET /wp-login.php)
         │
         ▼
┌─────────────────────┐
│ Rack::Attack layer  │
│ (requires gem)      │
└──────────┬──────────┘
           │
   ┌───────┴───────┐
   │ IP banned?    │
   └───────┬───────┘
           │
   YES ────┼──── NO
   │       │
   ▼       ▼
┌──────┐  ┌──────────────────────┐
│ 403  │  │ PestControl Engine   │
│ +tar │  │                      │
│ pit  │  │ 1. Log attempt       │
└──────┘  │ 2. Apply tarpit      │
          │ 3. Ban IP            │
          │ 4. Serve fake page   │
          └──────────────────────┘
```

### Ban Policy

- **First trap** = immediate ban (unless dry_run mode)
- **Ban duration**: 24 hours (configurable)
- **Legacy URLs**: configurable tolerance before ban (see Legacy Redirects)

## Requirements

- Rails 7.0+
- Ruby 3.0+
- **rack-attack** (recommended) - for IP blocking at Rack level

Without rack-attack, honeypots still work but banned IPs can reach Rails before being blocked.

## Installation

Add to your Gemfile:

```ruby
gem "pest_control", github: "ApaeP/pest_control"
gem "rack-attack"  # Recommended
```

Then run:

```bash
bundle install
rails generate pest_control:install
```

This creates:
- `config/initializers/pest_control.rb` - Configuration file
- Adds `mount PestControl::Engine => "/"` to your routes

### Why Mount on "/"?

The engine must be mounted at the root to intercept paths like `/wp-login.php`. **All application routes are resolved first; the engine only catches unresolved paths.** This means your existing routes always take precedence - PestControl acts as a smart catch-all for suspicious paths that would otherwise return 404. To see all captured routes:

```bash
rake pest_control:routes
```

## Configuration

### Basic Configuration

```ruby
# config/initializers/pest_control.rb
PestControl.configure do |config|
  # Banning
  config.ban_duration = 24.hours
  config.banning_enabled = true
  config.dry_run = false  # Set true to test without banning

  # Tarpit (enabled by default)
  config.tarpit_enabled = true
  config.tarpit_base_delay = 2
  config.tarpit_max_delay = 10

  # Credentials (hashed by default)
  config.credentials_storage = :hash_password  # :disabled, :username_only, :full

  # Logging
  config.log_level = :warn  # :debug, :info, :warn, :error
  config.sentry_enabled = true
end
```

### Configuration Profiles

#### Safe (Default)

Conservative settings for production. Minimal resource usage.

```ruby
PestControl.configure do |config|
  config.endless_stream_enabled = false
  config.tarpit_max_delay = 10
  config.credentials_storage = :hash_password
end
```

#### Moderate

Balanced security with some aggressive features.

```ruby
PestControl.configure do |config|
  config.endless_stream_enabled = true
  config.endless_stream_random_chance = 10
  config.tarpit_max_delay = 20
  config.credentials_storage = :hash_password
end
```

#### Aggressive

Maximum annoyance for bots. **Use with caution** - can block many Puma threads.

```ruby
PestControl.configure do |config|
  config.endless_stream_enabled = true
  config.endless_stream_random_chance = 25
  config.endless_stream_threshold = 3
  config.max_stream_chunks = 200_000  # ~200MB per session
  config.tarpit_max_delay = 30
  config.credentials_storage = :full
end
```

## Features

### Tarpit (Progressive Delays)

Wastes bot time by introducing delays before responding.

```ruby
config.tarpit_enabled = true
config.tarpit_base_delay = 2       # Base delay in seconds
config.tarpit_max_delay = 10       # Maximum delay
config.tarpit_increment_per_visit = 0.5  # Added per visit
config.max_concurrent_tarpits = 10 # Prevent thread exhaustion
```

Delay formula: `delay = base + (visit_count × increment)`, capped at `max_delay`.

| Visit | Delay |
|-------|-------|
| 1 | 2.5s |
| 5 | 4.5s |
| 16+ | 10s (max) |

### Endless Stream (Disabled by Default)

Sends garbage data to waste bot resources. **Blocks a Puma thread** for the duration.

> **Thread blocking context**: This affects Puma's thread pool within a single worker. In cluster mode with multiple workers, the impact is isolated per worker. If you use an async server (Falcon) or process requests in background jobs (Sidekiq), this limitation doesn't apply. The `max_concurrent_streams` setting is your primary safeguard.

```ruby
config.endless_stream_enabled = true
config.endless_stream_threshold = 5      # Visits before activation
config.endless_stream_random_chance = 15 # Random chance (0-100%)
config.max_concurrent_streams = 5        # Prevent self-DoS
config.max_stream_chunks = 50_000        # ~50MB per session (configurable)
config.overflow_action = :rickroll       # When limits reached
```

#### Throughput Calculation

| Chunks | Chunk Size | Delay Range | Data Sent | Duration |
|--------|------------|-------------|-----------|----------|
| 50,000 | 1KB | 0.1-0.5s | ~50MB | 1.5-7 hours |
| 200,000 | 1KB | 0.1-0.5s | ~200MB | 6-28 hours |
| 500,000 | 2KB | 0.05-0.2s | ~1GB | 7-28 hours |

To send GBs of data, increase `max_stream_chunks` and/or `stream_chunk_size`.

#### Overflow Actions

When `max_concurrent_streams` or `max_concurrent_tarpits` is reached:

| Action | Description |
|--------|-------------|
| `:rickroll` | Redirect to YouTube (default, zero blocking) |
| `:block` | Instant 403 response |
| `:tarpit` | Use tarpit if slots available |
| `"https://..."` | Custom redirect URL |

### Fake WordPress Pages

- `/wp-login.php` - Realistic login page with credential capture
- `/wp-admin/*` - Redirects to fake login
- `/xmlrpc.php` - Fake XML-RPC endpoint
- `/wp-content/*`, `/wp-includes/*`, `/wp-json/*` - Catch-all traps

### Browser Fingerprinting

Captures bot fingerprints via a tracking pixel **embedded only in honeypot responses** (fake login page, etc.). This does **not** affect legitimate users browsing your site - the fingerprinting script is never served on your application pages.

```ruby
config.fingerprinting_enabled = true
```

Collects: screen size, timezone, language, WebGL renderer, etc. Data is stored per-IP and associated with trap records.

### Legacy Redirects

For sites migrated from PHP/ASP, avoid banning legitimate visitors following old links:

```ruby
config.legacy_redirects_enabled = true
config.legacy_extensions = %w[php xml asp]
config.legacy_mappings = {
  "/old-page.php" => "/new-page",
  "/feed.xml" => "/rss"
}
config.legacy_strip_extension = true  # /contact.php → /contact
config.legacy_tolerance = 5           # GET visits before ban
```

## Data Handling

### Credentials Storage Modes

| Mode | Username | Password | Use Case |
|------|----------|----------|----------|
| `:hash_password` | Clear | SHA256 hash | **Default** - Safe analysis |
| `:username_only` | Clear | Not stored | Minimal data collection |
| `:disabled` | Not stored | Not stored | Maximum privacy |
| `:full` | Clear | Clear | Threat research (use with caution) |

```ruby
config.credentials_storage = :hash_password
```

### Header Redaction

Sensitive headers are **never logged**, even if present:

```ruby
# Default redacted headers
config.redacted_headers = %w[Cookie Authorization X-Api-Key X-Auth-Token X-CSRF-Token]

# Add custom headers
config.redacted_headers << "X-Custom-Secret"
```

### Data Retention

```ruby
config.trap_records_retention = 3.years  # Default
# config.trap_records_retention = 1.year
# config.trap_records_retention = nil     # Keep forever
```

Clean up expired records:

```bash
rake pest_control:cleanup
```

Or in code: `PestControl::TrapRecord.cleanup_expired!`

### GDPR Compliance

If using Memory Mode, inform users in your privacy policy:

> **Protection Against Automated Attacks**
>
> This website uses a security system ([PestControl](https://github.com/ApaeP/pest_control)) to protect against malicious bots. When a suspicious request is detected (attempts to access non-existent paths such as `/wp-login.php`), the following data may be collected:
>
> - IP address
> - Browser User-Agent
> - Requested URL and HTTP headers (sensitive headers redacted)
> - Submitted credentials (passwords are hashed, never stored in clear)
>
> This data is collected based on our legitimate interest (Article 6.1.f of GDPR) to protect our infrastructure. Data is retained for a maximum of 3 years.

## Observability

### Log Format

```
[PEST_CONTROL] 🍯 BOT TRAPPED: {"type":"FAKE_LOGIN_VIEW","ip":"1.2.3.4",...}
[PEST_CONTROL] ⏳ Tarpit: 1.2.3.4 - visit #1 - 2.5s delay
[PEST_CONTROL] 🔨 IP BANNED: 1.2.3.4 - Reason: honeypot:FAKE_LOGIN_VIEW
[PEST_CONTROL] 🌊 ENDLESS STREAM ACTIVATED: 1.2.3.4 (visit #5)
[PEST_CONTROL] 💀 BOT CRASHED: 1.2.3.4 after 847 chunks (~847KB) - IOError
```

### Metrics Callback

```ruby
config.on_metrics = ->(data) {
  # data structure:
  # {
  #   event: :trap | :ban | :ban_skipped | :unban | :stream_start | :stream_crash | :fingerprint,
  #   ip: "1.2.3.4",
  #   type: "FAKE_LOGIN_VIEW",  # for trap events
  #   reason: "honeypot:...",    # for ban events
  #   timestamp: Time.current
  # }

  # Prometheus
  PEST_CONTROL_EVENTS.labels(event: data[:event]).increment

  # StatsD
  StatsD.increment("pest_control.#{data[:event]}")
}
```

### Event Types

| Event | Description | Extra Fields |
|-------|-------------|--------------|
| `:trap` | Bot hit a honeypot | `type`, `ip` |
| `:ban` | IP was banned | `ip`, `reason` |
| `:ban_skipped` | Ban skipped (dry run) | `ip`, `reason` |
| `:unban` | IP was unbanned | `ip` |
| `:stream_start` | Endless stream started | `ip`, `visit_count` |
| `:stream_crash` | Bot disconnected during stream | `ip`, `chunks_sent` |
| `:fingerprint` | Fingerprint captured | `ip`, `data` |

### Sentry Integration

When Sentry is available and enabled:

```ruby
config.sentry_enabled = true
```

Events are sent with:
- Level: `warning`
- Extra data: full trap data
- Message: `[PEST_CONTROL] Bot trapped: {type}`

## rack-attack Integration

### Installation

```ruby
# Gemfile
gem "rack-attack"
```

No additional configuration required. When rack-attack is detected, PestControl automatically registers:
- A **blocklist** rule to block banned IPs before they reach Rails
- A **throttle** rule for suspicious user-agents (10 req/min)
- Custom **responders** for blocked/throttled requests (with tarpit delay)

Your existing rack-attack rules (if any) remain untouched.

### What rack-attack Provides

| Feature | With rack-attack | Without |
|---------|------------------|---------|
| Block banned IPs at Rack level | ✅ | ❌ (blocked at Rails level) |
| Tarpit delay for blocked requests | ✅ | ❌ |
| User-Agent throttling | ✅ | ❌ |

### Cache Store Recommendation

For reliable IP banning with concurrent writes, use Redis:

```ruby
# config/environments/production.rb
config.cache_store = :redis_cache_store, { url: ENV["REDIS_URL"] }
```

The `banned_ips` method may not list 100% of banned IPs with non-atomic cache stores, but `banned?(ip)` is always reliable.

## Memory Mode (Dashboard)

Persist trap records in your database and access an analysis dashboard.

### Setup

```bash
rails generate pest_control:memory
rails db:migrate
```

### Configuration

```ruby
config.memory_enabled = true

# Authentication - Option 1: HTTP Basic Auth
config.dashboard_username = "admin"
config.dashboard_password = ENV["PEST_CONTROL_PASSWORD"]

# Authentication - Option 2: Custom lambda
config.dashboard_auth = ->(controller) { controller.current_user&.admin? }

# Auto-refresh dashboard (optional, in seconds)
config.dashboard_auto_refresh = 60  # nil to disable (default)
```

### Dashboard Features

Access at `/pest-control/lab`:

- **Stats with Trends**: Total specimens, daily comparison, credentials captured
- **7-Day Activity Chart**: Visual bar chart of recent activity
- **Trap Distribution**: Which traps catch the most bots
- **Top User Agents**: Most common bot signatures
- **Activity Heatmap**: Day/hour grid showing attack patterns
- **Top Offenders**: IPs with most attempts (ban/unban)
- **Recent Records**: Latest 10 with link to full searchable list
- **CSV Export**: Download filtered records for analysis
- **Light/Dark Mode**: Automatic via system preference

### Query Examples

```ruby
PestControl::TrapRecord.today.count
PestControl::TrapRecord.yesterday.count
PestControl::TrapRecord.by_ip("1.2.3.4")
PestControl::TrapRecord.with_credentials
PestControl::TrapRecord.stats

# Analytics methods
PestControl::TrapRecord.daily_stats(days: 7)     # Last 7 days breakdown
PestControl::TrapRecord.user_agent_stats(limit: 10)  # Top user agents
PestControl::TrapRecord.hourly_heatmap           # Activity by day/hour
PestControl::TrapRecord.compare_period(period: :day) # Today vs yesterday
```

## API Reference

### Module Methods

```ruby
# Banning
PestControl.ban_ip!(ip, reason)
PestControl.unban_ip!(ip)
PestControl.banned?(ip)
PestControl.banned_ips
PestControl.clear_all_bans!

# Visit tracking
PestControl.get_visit_count(ip)
PestControl.reset_visit_count(ip)

# Credentials
PestControl.sanitize_credentials(raw_credentials)
PestControl.capture_credentials?
PestControl.credentials_storage_mode

# Status
PestControl.dry_run?
PestControl.tarpit_enabled?
PestControl.endless_stream_enabled?
PestControl.memory_enabled?
```

### Rake Tasks

```bash
rake pest_control:routes   # List all honeypot routes
rake pest_control:config   # Show current configuration
rake pest_control:banned   # List banned IPs
rake pest_control:clear_bans  # Clear all bans
rake pest_control:cleanup  # Delete expired trap records
```

## Testing

### Dry Run Mode

Test in production without banning:

```ruby
config.dry_run = true
```

### Disable Banning

For development/testing:

```ruby
config.banning_enabled = false
config.log_level = :debug
```

## Author's note & Why This Exists

It's a peaceful morning. You're sipping coffee, checking your Rails app logs, feeling like a mildly responsible developer. And then you see these again:

```
ActionController::RoutingError (No route matches [GET] "/wp-login.php")
ActionController::RoutingError (No route matches [GET] "/xmlrpc.php")
ActionController::RoutingError (No route matches [GET] "/wp-admin/admin-ajax.php")
```

**IT'S. NOT. WORDPRESS.**

So instead of just ignoring these requests like a normal, well-adjusted person, I decided to build this gem. Because if bots want to find WordPress so badly, let's give them the WordPress experience of their dreams:

- A fake login page that looks real enough to fool their scripts
- A tarpit that makes them wait
- An endless stream of garbage data
- Automatic IP banning

Is it over-engineered? Maybe.
Is it petty? 100%.
Does it spark joy? Yeah.

## Uninstallation

To remove PestControl from your application, run:

```bash
rails generate pest_control:uninstall
```

This will:
- Clear all cached bans and visit data
- Create a migration to drop the `trap_records` table (if Memory Mode was enabled)
- Remove the initializer file

After running the generator, you need to manually:

1. **Remove from `config/routes.rb`:**

```ruby
# Remove this line
mount PestControl::Engine => "/"
```

2. **Remove from `Gemfile`:**

```ruby
# Remove this line
gem "pest_control", github: "ApaeP/pest_control"
```

3. **Run migrations and bundle:**

```bash
rails db:migrate  # If Memory Mode was enabled
bundle install
```

## Contributing

Found a bug? Want to add a feature? **PRs are welcome.**

1. Fork it
2. Create your feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes (`git commit -am 'Add my feature'`)
4. Push to the branch (`git push origin feature/my-feature`)
5. Open a Pull Request

## License

MIT
