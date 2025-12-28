# frozen_string_literal: true

require 'rails/generators'
require 'rails/generators/base'

module PestControl
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path('templates', __dir__)

      desc 'Installs PestControl in your Rails application'

      def create_initializer
        template 'initializer.rb', 'config/initializers/pest_control.rb'
      end

      def add_routes
        route 'mount PestControl::Engine => "/"'
      end

      def ask_about_memory_mode
        say ''
        say '🧠 Memory Mode', :cyan
        say '  Persist trap records in your database and access a dashboard to analyze bot activity.'
        say ''

        if yes?('  Would you like to enable Memory Mode? (y/n)')
          say '  Running memory mode generator...', :green
          generate 'pest_control:memory'
        else
          say '  Skipped. You can enable it later with:', :yellow
          say '    rails generate pest_control:memory'
          say ''
        end
      end

      def show_post_install_message
        say ''
        say '🍯 PestControl installed successfully!', :green
        say ''
        say '  • Initializer: config/initializers/pest_control.rb'
        say '  • Routes: mount PestControl::Engine => "/"'
        say ''
        say 'Bots scanning for WordPress will now:', :yellow
        say '  • See a fake login page (credentials captured)'
        say '  • Wait 2-30s per request (progressive tarpit)'
        say '  • Get banned for 24h after first trap'
        say '  • Receive GBs of garbage data (endless stream)'
        say ''
        say 'Enjoy! 🎉', :green
      end
    end
  end
end
