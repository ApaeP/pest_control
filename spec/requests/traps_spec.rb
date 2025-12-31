# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'PestControl::TrapsController', type: :request do # rubocop:disable Metrics/BlockLength
  before(:all) do
    Rails.application.routes.draw do
      mount PestControl::Engine => '/'
    end
  end

  describe 'GET /wp-login.php' do
    it 'returns the fake login page' do
      get '/wp-login.php'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('WordPress')
    end

    it 'bans the requesting IP' do
      get '/wp-login.php'

      expect(PestControl.banned?('127.0.0.1')).to be true
    end

    it 'calls on_bot_trapped callback' do
      trapped_data = nil
      PestControl.configuration.on_bot_trapped = ->(data) { trapped_data = data }

      get '/wp-login.php'

      expect(trapped_data).not_to be_nil
      expect(trapped_data[:type]).to eq('FAKE_LOGIN_VIEW')
      expect(trapped_data[:path]).to eq('/wp-login.php')
    end
  end

  describe 'POST /wp-login.php' do
    it 'captures credentials when enabled' do
      trapped_data = nil
      PestControl.configuration.on_bot_trapped = ->(data) { trapped_data = data }

      post '/wp-login.php', params: { log: 'admin', pwd: 'secret123' }

      expect(response).to have_http_status(:ok)
      expect(trapped_data[:type]).to eq('CREDENTIAL_CAPTURE')
      expect(trapped_data[:credentials][:username]).to eq('admin')
      expect(trapped_data[:credentials][:password]).to eq('secret123')
    end

    it 'does not capture credentials when disabled' do
      PestControl.configuration.capture_credentials = false
      trapped_data = nil
      PestControl.configuration.on_bot_trapped = ->(data) { trapped_data = data }

      post '/wp-login.php', params: { log: 'admin', pwd: 'secret123' }

      expect(trapped_data[:credentials]).to be_nil
    end
  end

  describe 'GET /wp-admin' do
    it 'redirects to wp-login.php' do
      get '/wp-admin'

      expect(response).to have_http_status(:redirect)
      expect(response.location).to include('wp-login.php')
    end
  end

  describe 'GET /xmlrpc.php' do
    it 'returns fake XML-RPC response' do
      get '/xmlrpc.php'

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include('xml')
      expect(response.body).to include('XML-RPC services are disabled')
    end
  end

  describe 'GET /*.php (catch-all)' do
    it 'returns fake Apache 404' do
      get '/random-file.php'

      expect(response).to have_http_status(:not_found)
      expect(response.body).to include('Apache')
      expect(response.body).to include('Not Found')
    end

    it 'works for various PHP paths' do
      %w[/admin.php /alfa.php /shell.php /config.php].each do |path|
        get path
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'GET /wp-content/*' do
    it 'returns 404 for WordPress content paths' do
      get '/wp-content/plugins/pwnd.php'

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'banned IP behavior' do
    before do
      PestControl.ban_ip!('127.0.0.1', 'test_ban')
    end

    it 'blocks subsequent requests from banned IPs' do
      expect(PestControl.banned?('127.0.0.1')).to be true
    end
  end

  describe 'visit counting integration' do
    it 'tracks visits across multiple requests' do
      PestControl.configuration.tarpit_enabled = true
      PestControl.configuration.tarpit_base_delay = 0
      PestControl.configuration.tarpit_increment_per_visit = 0

      trapped_counts = []
      PestControl.configuration.on_bot_trapped = lambda { |data|
        trapped_counts << data[:visit_count]
      }

      3.times { get '/wp-login.php' }

      expect(trapped_counts).to eq([1, 2, 3])
    end
  end

  describe 'GET /wp-admin/fp.gif (fingerprint capture)' do
    before do
      PestControl.configuration.fingerprinting_enabled = true
    end

    it 'returns a transparent GIF' do
      get '/wp-admin/fp.gif'

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include('image/gif')
    end

    it 'captures fingerprint data from query string' do
      fingerprint = { screen: '1920x1080', tz: 'Europe/Paris', lang: 'fr' }

      get "/wp-admin/fp.gif?#{CGI.escape(fingerprint.to_json)}"

      cache_key = "#{PestControl.configuration.cache_key_prefix}:fingerprint:127.0.0.1"
      cached_fp = Rails.cache.read(cache_key)

      expect(cached_fp).not_to be_nil
      expect(cached_fp[:screen]).to eq('1920x1080')
    end

    it 'returns 404 when fingerprinting is disabled' do
      PestControl.configuration.fingerprinting_enabled = false

      get '/wp-admin/fp.gif'

      expect(response).to have_http_status(:not_found)
    end
  end
end
