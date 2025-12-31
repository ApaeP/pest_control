# frozen_string_literal: true

require_relative 'boot'
require 'rails'
require 'active_record/railtie'
require 'action_controller/railtie'
require 'active_support/railtie'

Bundler.require(*Rails.groups)

require 'pest_control'

module Dummy
  class Application < Rails::Application
    config.load_defaults Rails::VERSION::STRING.to_f
    config.eager_load = false
    config.cache_store = :memory_store
    config.secret_key_base = "test_secret_key_base_for_pest_control_specs"
    config.root = File.expand_path("..", __dir__)
    config.active_record.maintain_test_schema = false
    config.consider_all_requests_local = true
    config.action_dispatch.show_exceptions = :none
  end
end
