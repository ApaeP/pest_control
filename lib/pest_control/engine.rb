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

    config.generators do |g|
      g.test_framework :rspec
    end
  end
end
