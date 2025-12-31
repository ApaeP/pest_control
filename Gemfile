# frozen_string_literal: true

source "https://rubygems.org"

gemspec

gem "rake"

rails_version = ENV.fetch("RAILS_VERSION", "8.1")

case rails_version
when "edge"
  gem "rails", github: "rails/rails", branch: "main"
else
  gem "rails", "~> #{rails_version}.0"
end

group :development, :test do
  gem "rspec-rails"
  gem "rubocop"
  gem "rubocop-rails"
  gem "rubocop-rspec"
  gem "simplecov", require: false
  gem "sqlite3"
end
