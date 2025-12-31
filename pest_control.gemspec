# frozen_string_literal: true

require_relative "lib/pest_control/version"

Gem::Specification.new do |spec|
  spec.name        = "pest_control"
  spec.version     = PestControl::VERSION
  spec.authors     = ["Your Name"]
  spec.email       = ["your.email@example.com"]
  spec.homepage    = "https://github.com/ApaeP/pest_control"
  spec.summary     = "Honeypot & tarpit for WordPress/PHP scanner bots"
  spec.description = "A Rails engine that traps bots scanning for WordPress/PHP vulnerabilities. " \
                     "Features include fake wp-login pages, credential harvesting, progressive tarpits, " \
                     "endless data streams to crash bots, and automatic IP banning via Rack::Attack."
  spec.license     = "MIT"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.post_install_message = <<~MSG

    🍯 PestControl installed!

    Run the generator to set up the honeypot:

        rails generate pest_control:install

    This will add the routes and create the initializer.
    Bots scanning for WordPress are about to have a bad time.

  MSG

  spec.files = Dir.chdir(__dir__) do
    Dir["{app,config,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  spec.required_ruby_version = ">= 3.0"

  spec.add_dependency "rack-attack", ">= 6.0"
  spec.add_dependency "rails", ">= 7.0"
end
