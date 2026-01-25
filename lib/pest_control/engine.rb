# frozen_string_literal: true

module PestControl
  class Engine < ::Rails::Engine
    isolate_namespace PestControl

    initializer "pest_control.assets" do |app|
    end

    initializer "pest_control.rack_attack" do |_app|
      PestControl::RackAttackRules.apply! if defined?(Rack::Attack)
    end

    initializer "pest_control.append_routes" do |app|
    end

    initializer "pest_control.check_dependencies", after: :load_config_initializers do
      config.after_initialize do
        next if defined?(Rack::Attack)
        next unless PestControl.configuration.banning_enabled

        message = <<~MSG
          [PEST_CONTROL] WARNING: rack-attack gem is not installed.

          Without rack-attack, the following features are disabled:
            - IP banning at Rack level (banned IPs can still reach Rails)
            - Tarpit delay for blocked requests
            - User-Agent throttling

          The honeypot traps still work, but banned IPs won't be blocked at the Rack level.

          To fix this, add to your Gemfile:
            gem "rack-attack"

          Then run: bundle install

          To disable this warning, set: config.banning_enabled = false
        MSG

        if Rails.logger
          Rails.logger.warn(message)
        else
          warn message
        end
      end
    end

    config.generators do |g|
      g.test_framework :rspec
    end

    rake_tasks do
      load File.expand_path("../tasks/pest_control.rake", __dir__)
    end
  end
end
