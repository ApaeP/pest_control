# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record/migration"

module PestControl
  module Generators
    class UninstallGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      desc "Removes PestControl from your application"

      def clear_cached_data
        say ""
        say "Clearing cached data...", :yellow

        return unless defined?(Rails) && Rails.application

        begin
          PestControl.clear_all_bans!
          say "  Cleared all IP bans", :green
        rescue StandardError => e
          say "  Could not clear bans: #{e.message}", :yellow
        end

        begin
          cache = PestControl.cache
          if cache.respond_to?(:delete_matched)
            cache.delete_matched("pest_control:*")
            say "  Cleared cache entries", :green
          else
            say "  Cache does not support delete_matched, skip manual cleanup", :yellow
          end
        rescue StandardError => e
          say "  Could not clear cache: #{e.message}", :yellow
        end
      end

      def create_drop_migration
        return unless memory_mode_installed?

        say ""
        say "Creating migration to drop trap_records table...", :yellow
        migration_template(
          "drop_trap_records.rb.erb",
          "db/migrate/drop_pest_control_trap_records.rb"
        )
      end

      def remove_initializer
        initializer_path = "config/initializers/pest_control.rb"
        return unless File.exist?(initializer_path)

        remove_file initializer_path
        say "  Removed #{initializer_path}", :green
      end

      def show_manual_steps
        say ""
        say "Manual steps remaining:", :yellow
        say ""
        say "  1. Remove from config/routes.rb:", :cyan
        say '     mount PestControl::Engine => "/"'
        say ""
        say "  2. Remove from Gemfile:", :cyan
        say '     gem "pest_control"'
        say ""
        say "  3. Run:", :cyan
        say "     bundle install"

        if memory_mode_installed?
          say ""
          say "  4. Run the migration:", :cyan
          say "     rails db:migrate"
        end

        say ""
        say "PestControl has been removed. Goodbye! 👋", :green
        say ""
      end

      private

      def memory_mode_installed?
        ActiveRecord::Base.connection.table_exists?(:pest_control_trap_records)
      rescue StandardError
        false
      end
    end
  end
end
