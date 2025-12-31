# 🦠 PestControl

[![CI](https://github.com/ApaeP/pest_control/actions/workflows/ci.yml/badge.svg)](https://github.com/ApaeP/pest_control/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/ApaeP/pest_control/graph/badge.svg)](https://codecov.io/gh/ApaeP/pest_control)
[![Ruby](https://img.shields.io/badge/ruby-3.4-CC342D.svg?logo=ruby)](https://www.ruby-lang.org/)
[![Rails](https://img.shields.io/badge/rails-8.1-D30001.svg?logo=rubyonrails)](https://rubyonrails.org/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](MIT-LICENSE)

A configurable Rails gem to trap bots scanning your site for WordPress/PHP vulnerabilities.

## Why This Exists (A Rant)

It's a peaceful morning. You're sipping coffee, checking your Rails app logs, feeling like a mildly responsible developer. And then you see these again, for the 69420th time this month:

```
ActionController::RoutingError (No route matches [GET] "/wp-login.php")
ActionController::RoutingError (No route matches [GET] "/xmlrpc.php")
ActionController::RoutingError (No route matches [GET] "/wp-admin/admin-ajax.php")
ActionController::RoutingError (No route matches [GET] "/alfa.php")
ActionController::RoutingError (No route matches [GET] "/adminfuns.php")
ActionController::RoutingError (No route matches [GET] "/wp-content/plugins/pwnd/as.php")
```

**IT'S. NOT. WORDPRESS.**

It's a Rails app. It has always been a Rails app. There is no `wp-login.php`, and there never will be. And yet, every single day, some dumb*** bot from the depths of the internet decides that maybe this time there's a juicy WordPress installation hiding behind that Ruby code.

So instead of just ignoring these requests like a normal, well-adjusted person, I decided to waste a perfectly good morning writing this gem. Because if bots want to find WordPress so badly, let's give them the WordPress experience of their dreams:

- A fake login page that looks real enough (hopefully) to fool their scripts
- A tarpit that makes them wait for as long as your server allows
- An endless stream of garbage data to (hopefully) make their memory go boom
- Automatic IP banning because revenge

Is it over-engineered? Depends, but the fact that I spent more than 2 hours on this might be an indication that it is.
Is it petty? 100%.
Does it spark joy? Yeah.

### ⚠️ Disclaimer

This is `v0.0.1`. I built this in a fit of rage. It's not optimized, nor really tested for production. It probably has bugs. But hey, it works on my machine™ 👨‍💻.

If you want to laugh at my code, improve it, or add more ways to mess with bots, **PRs are welcome**. Let's be chaotic together 😄.

## Features

- 🎣 **Fake wp-login**: Realistic WordPress login page that captures credential attempts
- ⏳ **Progressive tarpit**: The more they return, the longer they wait (2s → 30s)
- 🌊 **Endless stream**: Sends GBs of garbage data to crash bots
- 🔨 **Automatic IP banning**: IPs are banned after being trapped
- 🔍 **Fingerprinting**: Collects bot info (canvas, WebGL, timezone, etc.)
- 📊 **Detailed logging**: IP, User-Agent, headers, login attempts...
- 🚨 **Sentry integration**: Events sent automatically
- 🧪 **Memory Mode**: Persist trap records in DB with a beautiful dashboard
- 🔄 **Legacy Redirects**: Handle old PHP/ASP URLs from site migrations
- 📈 **Metrics callbacks**: Integrate with Prometheus, StatsD, etc.
- 🧪 **Dry Run mode**: Test without actually banning
- ⚙️ **Fully configurable**: Every behavior can be customized

## ⚠️ Performance Considerations

### Thread Blocking

Both **Tarpit** and **Endless Stream** use `sleep()` which **blocks a Puma worker thread**. This is intentional (we want to waste bot resources), but you should be aware:

| Feature | Max Duration | Risk |
|---------|--------------|------|
| Tarpit | 30 seconds (default) | Medium |
| Endless Stream | Minutes to hours | High |

**Protections:**

1. **Concurrent stream limit** — Only 5 endless streams can run simultaneously (`max_concurrent_streams`).

2. **Concurrent tarpit limit** — Only 10 tarpits can run simultaneously (`max_concurrent_tarpits`).

3. When either limit is reached, the `overflow_action` is used:
   - `:rickroll` (default) — Instant redirect to YouTube, zero thread blocking 🎵
   - `:block` — Instant 403, zero thread blocking
   - `:tarpit` — 10s delay (only if tarpit slots available, else rickroll)
   - `"https://..."` — Custom redirect URL

4. **Use with Rack::Timeout** — PestControl respects Rack::Timeout. If you have it configured, requests will be terminated at the timeout limit.

**Recommendations:**

1. **Monitor your worker pool** — If you see high worker saturation during bot attacks, consider:
   - Increasing `max_concurrent_streams` if you have many workers
   - Reducing `tarpit_max_delay`
   - Lowering `endless_stream_random_chance`

2. **Consider your traffic** — On low-traffic sites, this is rarely an issue. On high-traffic sites with many bots, you may want to disable the more aggressive features.

### Dry Run Mode

Test PestControl in production without actually banning IPs:

```ruby
PestControl.configure do |config|
  config.dry_run = true  # Logs everything but doesn't ban
end
```

### Metrics Integration

Track PestControl events in your monitoring system:

```ruby
PestControl.configure do |config|
  config.on_metrics = ->(data) {
    # data = { event: :trap|:ban|:stream_start|:fingerprint, ip:, timestamp:, ... }

    # Prometheus example
    PEST_CONTROL_EVENTS.labels(event: data[:event]).increment

    # StatsD example
    StatsD.increment("pest_control.#{data[:event]}")
  }
end
```

## Installation

Add the gem to your Gemfile:

```ruby
gem "pest_control", github: "ApaeP/pest_control"
```

Then run:

```bash
bundle install
rails generate pest_control:install
```

This will:
- Create `config/initializers/pest_control.rb`
- Add `mount PestControl::Engine => "/"` to your routes

## Configuration

The initializer contains all available options:

```ruby
PestControl.configure do |config|
  # ============================================================================
  # BANNING
  # ============================================================================
  config.ban_duration = 24.hours           # How long IPs stay banned
  config.banning_enabled = true            # Set false to disable
  config.dry_run = false                   # Log but don't ban (for testing)

  # ============================================================================
  # ENDLESS STREAM
  # ============================================================================
  config.endless_stream_enabled = true     # Enable/disable feature
  config.endless_stream_threshold = 5      # Visits before activating
  config.endless_stream_random_chance = 15 # Random chance (0-100%)
  config.max_concurrent_streams = 5        # Prevent self-DoS
  config.overflow_action = :rickroll       # :rickroll, :block, :tarpit, or URL
  config.max_stream_chunks = 50_000        # Max ~50MB per session
  config.stream_chunk_size = 1024          # Bytes per chunk
  config.stream_chunk_delay_min = 0.1      # Min delay between chunks
  config.stream_chunk_delay_max = 0.5      # Max delay between chunks

  # ============================================================================
  # TARPIT
  # ============================================================================
  config.tarpit_enabled = true             # Enable/disable feature
  config.tarpit_base_delay = 2             # Base delay (seconds)
  config.tarpit_max_delay = 30             # Maximum delay (seconds)
  config.tarpit_increment_per_visit = 0.5  # Added per visit (seconds)
  config.max_concurrent_tarpits = 10       # Prevent self-DoS
  config.banned_ip_tarpit_min = 5          # Min delay for banned IPs
  config.banned_ip_tarpit_max = 10         # Max delay for banned IPs

  # ============================================================================
  # VISIT TRACKING
  # ============================================================================
  config.visit_count_ttl = 1.hour          # How long to remember visits
  config.cache_key_prefix = "pest_control"  # Cache key prefix

  # ============================================================================
  # LOGGING
  # ============================================================================
  config.log_level = :warn                 # :debug, :info, :warn, :error
  config.sentry_enabled = true             # Send events to Sentry
  config.logger = Rails.logger             # Custom logger
  config.cache = Rails.cache               # Custom cache

  # ============================================================================
  # CALLBACKS
  # ============================================================================

  # Called when a bot is trapped
  config.on_bot_trapped = ->(data) {
    BotAttempt.create!(data)               # Save to database
    SlackNotifier.ping("Bot: #{data[:ip]}")
  }

  # Called when an IP is banned
  config.on_ip_banned = ->(ip, reason) {
    Firewall.block_ip(ip)                  # Add to external blocklist
  }

  # Called when endless stream starts
  config.on_endless_stream_start = ->(ip, visit_count) {
    puts "💀 Destroying #{ip}..."
  }

  # Called when bot crashes during endless stream
  config.on_bot_crashed = ->(ip, chunks_sent, error) {
    puts "🎉 #{ip} crashed after #{chunks_sent}KB!"
  }

  # ============================================================================
  # CREDENTIAL CAPTURE
  # ============================================================================
  config.capture_credentials = true        # Log captured credentials
  config.fingerprinting_enabled = true     # Enable JS fingerprinting

  # ============================================================================
  # FAKE PAGES
  # ============================================================================
  config.fake_site_name = "WordPress"      # Name shown on fake login
  config.custom_blocked_html = nil         # Custom 403 page HTML
  config.custom_login_html = nil           # Custom login page HTML

  # ============================================================================
  # USER AGENTS
  # ============================================================================
  config.suspicious_user_agents << /my-bot/i  # Add custom user agents to throttle
end
```

## How It Works

### Request Flow

```
Bot requests /wp-login.php
         │
         ▼
   ┌─────────────────┐
   │  Rack::Attack   │
   │  Is IP banned?  │
   └────────┬────────┘
            │
    ┌───────┴───────┐
    │               │
   YES              NO
    │               │
    ▼               ▼
┌─────────┐   ┌──────────────────┐
│  403    │   │ HoneypotController│
│ Blocked │   │                  │
│ +tarpit │   │ 1. Log attempt   │
└─────────┘   │ 2. Count visits  │
              │ 3. Tarpit OR     │
              │    Endless stream│
              │ 4. Serve fake    │
              │    login page    │
              │ 5. Ban IP        │
              └──────────────────┘
```

### Tarpit Delay Formula

```
delay = base_delay + (visit_count × increment_per_visit)
delay = min(delay, max_delay)
```

Example with defaults:
| Visit | Delay |
|-------|-------|
| 1 | 2.5s |
| 2 | 3.0s |
| 5 | 4.5s |
| 10 | 7.0s |
| 56+ | 30s (max) |

### Endless Stream

After threshold visits (or random chance), the server:
1. Starts HTTP streaming response
2. Sends ~1KB chunks every 100-500ms
3. Bot accumulates data in memory
4. Eventually crashes or times out

## Paths Covered

Default patterns catch:
- `*.php` (any PHP file)
- `/wp-login.php`, `/wp-admin/*`
- `/wp-content/*`, `/wp-includes/*`
- `/xmlrpc.php`
- `/phpmyadmin`, `/phpMyAdmin`
- `/administrator`, `/admin.php`
- `/.env`, `/.git/*`
- `/backup`, `/bak`, `/old`, `/tmp`
- Known webshells: `/c99`, `/r57`, `/alfa`, `/wso`

## 🔄 Legacy Redirects

If your site was migrated from PHP, ASP, or another platform, you might have old backlinks (from Wikipedia, blogs, etc.) pointing to legacy URLs like `/contact.php`. By default, PestControl would ban these legitimate visitors.

Enable Legacy Redirects to handle them gracefully:

```ruby
PestControl.configure do |config|
  config.legacy_redirects_enabled = true
  config.legacy_extensions = %w[php xml asp]

  # Custom mappings (optional, takes priority)
  config.legacy_mappings = {
    "/periode3.php" => "/periode-3",
    "/feed.xml"     => "/rss"
  }

  # Auto-strip extension: /contact.php → /contact (default: true)
  config.legacy_strip_extension = true

  # Allow 5 visits on unmapped URLs before banning (default: 5)
  config.legacy_tolerance = 5

  # Log redirects as trap records (default: false)
  config.legacy_log_redirects = false
end
```

### How It Works

```
GET /contact.php arrives
         │
         ▼
  ┌──────────────────────────┐
  │ Extension in legacy list?│
  └───────────┬──────────────┘
              │
      ┌───────┴───────┐
      NO              YES
      │               │
      ▼               ▼
   Normal         ┌─────────────────┐
   PestControl    │ Custom mapping? │
   (ban)          └────────┬────────┘
                           │
                   ┌───────┴───────┐
                   YES             NO
                   │               │
                   ▼               ▼
               301 to          Strip extension
               mapping         301 → /contact
```

### Behavior Summary

| Request | Result |
|---------|--------|
| `GET /periode3.php` (mapped) | 301 → `/periode-3` |
| `GET /contact.php` (strip enabled) | 301 → `/contact` |
| `GET /unknown.php` (visits 1-5) | 404 (no ban) |
| `GET /unknown.php` (visit 6+) | Ban |
| `POST /contact.php` | Ban (only GET is tolerated) |
| `GET /wp-login.php` (not in legacy_extensions) | Normal PestControl behavior |

## 🧪 Memory Mode (Dashboard)

Want to analyze your pest collection? Enable Memory Mode to persist trap records and access a beautiful dashboard.

### Setup

```bash
rails generate pest_control:memory
rails db:migrate
```

### Configuration

```ruby
PestControl.configure do |config|
  # Enable database persistence
  config.memory_enabled = true

  # Dashboard authentication - Option 1: HTTP Basic Auth
  config.dashboard_username = "admin"
  config.dashboard_password = ENV["PEST_CONTROL_DASHBOARD_PASSWORD"]

  # Dashboard authentication - Option 2: Custom lambda (takes precedence)
  # Example: only allow admin users
  config.dashboard_auth = ->(controller) { controller.current_user&.admin? }
end
```

### Dashboard

Access the dashboard at `/pest-control/lab` to see:
- 📊 **Stats**: Total specimens, unique IPs, credentials captured
- 🎯 **Trap Types Distribution**: Which traps are catching the most bots
- 🏆 **Top Offenders**: IPs with the most attempts (ban/unban from here)
- 📋 **Recent Specimens**: Detailed log of all trap records
- 🔒 **Banned IPs**: View and manage bans

### Model

The `PestControl::TrapRecord` model stores:
- IP, path, method, user agent, referer
- Headers and request params
- Captured credentials
- Browser fingerprint data
- Visit count and endless stream flag

```ruby
# Query examples
PestControl::TrapRecord.today.count
PestControl::TrapRecord.by_ip("1.2.3.4")
PestControl::TrapRecord.with_credentials
PestControl::TrapRecord.stats

# Clean up old records (run periodically via cron/Sidekiq)
PestControl::TrapRecord.cleanup_expired!
```

### Data Retention

By default, trap records are kept for **3 years**. You can configure this:

```ruby
PestControl.configure do |config|
  config.trap_records_retention = 3.years  # Default
  # config.trap_records_retention = 1.year
  # config.trap_records_retention = nil    # Keep forever
end
```

To clean up expired records, run periodically:

```ruby
# In a Rake task, cron job, or Sidekiq scheduled job
PestControl::TrapRecord.cleanup_expired!
```

### Legal Notice Example

If you're using Memory Mode, you should inform users in your privacy policy. Here's an example paragraph you can adapt:

#### Privacy Policy

> **Protection Against Automated Attacks**
>
> This website uses a security system to protect against malicious bots ([PestControl](https://github.com/ApaeP/pest_control)). When a suspicious request is detected (attempts to access non-existent paths such as `/wp-login.php`, `/xmlrpc.php`, or any `.php` file), the following data may be collected and retained for a maximum of 3 years:
>
> - IP address
> - Browser User-Agent
> - Requested URL and HTTP headers
> - Submitted credentials (in case of fraudulent login attempts)
>
> This data is collected based on our **legitimate interest** (Article 6.1.f of GDPR) to protect our infrastructure against unauthorized access and intrusion attempts.
>
> This information is not shared with third parties and is only used for security and threat analysis purposes. No data is collected by PestControl during normal browsing of the website.

## Managing Banned IPs

```ruby
# View all banned IPs
PestControl.banned_ips
# => {"1.2.3.4" => {banned_at: ..., reason: ..., expires_at: ...}}
> **Note on `banned_ips`**: This method may not always list 100% of banned IPs due to the way Rails.cache handles concurrent writes. However, this does not affect the actual banning mechanism — `banned?` checks each IP individually and is always reliable. For atomic operations (SADD, etc.), consider using Redis as your Rails cache store.

# Check if an IP is banned
PestControl.banned?("1.2.3.4")
# => true

# Unban an IP
PestControl.unban_ip!("1.2.3.4")

# Unban all IPs
PestControl.clear_all_bans!

# Get visit count for an IP
PestControl.get_visit_count("1.2.3.4")
# => 3

# Reset visit count
PestControl.reset_visit_count("1.2.3.4")
```

## Log Output

```
[PEST_CONTROL] 🍯 BOT TRAPPED: {"type":"FAKE_LOGIN_VIEW","ip":"4.217.237.222",...}
[PEST_CONTROL] ⏳ Tarpit: 4.217.237.222 - visit #1 - 2.5s delay
[PEST_CONTROL] 🔨 IP BANNED: 4.217.237.222 - Reason: honeypot:FAKE_LOGIN_VIEW
[PEST_CONTROL] 🍯 BOT TRAPPED: {"type":"CREDENTIAL_CAPTURE","credentials":{...},...}
[PEST_CONTROL] 🌊 ENDLESS STREAM ACTIVATED: 4.217.237.222 (visit #5)
[PEST_CONTROL] 💀 BOT CRASHED: 4.217.237.222 after 847 chunks (~847KB) - IOError
[PEST_CONTROL] 🚫 BLOCKED (banned IP): 4.217.237.222 -> /wp-login.php
```

## Testing

To test without banning real IPs:

```ruby
# config/initializers/pest_control.rb
PestControl.configure do |config|
  config.banning_enabled = false  # Disable banning
  config.log_level = :debug       # Verbose logging
end
```

## Requirements

- Rails 7.0+
- Ruby 3.0+
- rack-attack gem

## Contributing

Found a bug? Want to add a feature? Have an even more diabolical way to mess with bots? **I'm here for it.**

This gem was born from frustration and built with spite. If that energy resonates with you, let's collaborate:

1. Fork it
2. Create your feature branch (`git checkout -b feature/even-more-chaos`)
3. Commit your changes (`git commit -am 'Add rickroll redirect for repeat offenders'`)
4. Push to the branch (`git push origin feature/even-more-chaos`)
5. Open a Pull Request

No contribution is too unhinged. Well, maybe some are. But let's find out together.

## License

MIT
