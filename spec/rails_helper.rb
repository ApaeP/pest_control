# frozen_string_literal: true

require "spec_helper"

ENV["RAILS_ENV"] ||= "test"

require_relative "dummy/config/environment"

require "rspec/rails"

ActiveRecord::Base.establish_connection

ActiveRecord::Base.connection.drop_table(:pest_control_trap_records, if_exists: true)

require_relative "dummy/db/migrate/20241228000001_create_pest_control_trap_records"
CreatePestControlTrapRecords.new.change

RSpec.configure do |config|
  config.infer_spec_type_from_file_location!
  config.use_transactional_fixtures = true

  config.before do
    PestControl.configuration = PestControl::Configuration.new
    PestControl.configuration.banning_enabled = true
    PestControl.configuration.tarpit_enabled = false
    PestControl.configuration.endless_stream_enabled = false
    Rails.cache.clear
  end
end
