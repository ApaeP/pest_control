# frozen_string_literal: true

require "rails/generators"
require "rails/generators/base"

module PestControl
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Installs PestControl in your Rails application"

      def create_initializer
        template "initializer.rb", "config/initializers/pest_control.rb"
      end

      def add_routes
        route 'mount PestControl::Engine => "/"'
      end

      def ask_about_memory_mode
        say ""
        say "🧠 Memory Mode", :cyan
        say "  Persist trap records in your database and access a dashboard to analyze bot activity."
        say ""

        if yes?("  Would you like to enable Memory Mode? (y/n)")
          say "  Running memory mode generator...", :green
          generate "pest_control:memory"
        else
          say "  Skipped. You can enable it later with:", :yellow
          say "    rails generate pest_control:memory"
          say ""
        end
      end

      def show_post_install_message
        say ""
        say "PestControl installed successfully!", :green
        say ""
        say "Files created:"
        say "  • config/initializers/pest_control.rb"
        say '  • Routes: mount PestControl::Engine => "/"'
        say ""
        say "Safe defaults enabled:", :cyan
        say "  • Tarpit: 2-10s delay per request"
        say "  • Credentials: passwords hashed (SHA256)"
        say "  • Endless stream: DISABLED (enable in config)"
        say "  • IPs banned for 24h after first trap"
        say ""
        say "Recommended: Install rack-attack for IP blocking at Rack level:", :yellow
        say "  gem 'rack-attack'"
        say ""
        say "Useful commands:"
        say "  rake pest_control:routes  # List all honeypot routes"
        say "  rake pest_control:config  # Show current configuration"
        say "  rake pest_control:banned  # List banned IPs"
        say ""
      end
    end
  end
end
