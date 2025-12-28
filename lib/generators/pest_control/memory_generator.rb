# frozen_string_literal: true

require 'rails/generators'
require 'rails/generators/active_record/migration'

module PestControl
  module Generators
    class MemoryGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration

      source_root File.expand_path('templates', __dir__)

      desc 'Enables Memory Mode - creates the migration for persisting trap records'

      def create_migration_file
        migration_template(
          'create_trap_records.rb.erb',
          'db/migrate/create_pest_control_trap_records.rb'
        )
      end

      def update_initializer
        initializer_path = 'config/initializers/pest_control.rb'
        full_path = Rails.root.join(initializer_path)

        if File.exist?(full_path)
          gsub_file initializer_path,
                    /# Enable database persistence \(default: false\)\n\s*# config\.memory_enabled = false/,
                    "# Enable database persistence\n  config.memory_enabled = true"

          say "  ✅ Enabled memory_enabled = true in #{initializer_path}", :green
        else
          say '  ⚠️  Initializer not found. Run `rails generate pest_control:install` first.', :yellow
        end
      end

      def show_post_install_message
        say ''
        say '🧠 Memory Mode enabled!', :green
        say ''
        say 'Next steps:', :yellow
        say '  1. Run `rails db:migrate` to create the trap_records table'
        say '  2. Configure dashboard authentication in config/initializers/pest_control.rb'
        say '  3. Access the dashboard at: /pest-control/lab'
        say ''
        say 'Your honeypot now has a memory. Bots beware! 🐝', :green
        say ''
      end
    end
  end
end
