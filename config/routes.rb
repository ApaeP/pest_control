# frozen_string_literal: true

PestControl::Engine.routes.draw do
  # ===========================================================================
  # DASHBOARD (Memory Mode)
  # ===========================================================================
  get  'pest-control/lab',            to: 'dashboard#lab', as: :pest_control_lab
  get  'pest-control/lab/records',    to: 'dashboard#records', as: :pest_control_records
  get  'pest-control/lab/record/:id', to: 'dashboard#show', as: :pest_control_record
  post 'pest-control/lab/unban/:ip',  to: 'dashboard#unban', as: :pest_control_unban, constraints: { ip: %r{[^/]+} }
  post 'pest-control/lab/ban/:ip',    to: 'dashboard#ban', as: :pest_control_ban, constraints: { ip: %r{[^/]+} }

  # ===========================================================================
  # TRAPS
  # ===========================================================================

  # Fake WordPress login
  get  'wp-login.php',  to: 'traps#fake_login'
  post 'wp-login.php',  to: 'traps#capture_credentials'
  get  'wp-login',      to: 'traps#fake_login'

  # XML-RPC (heavily targeted by attacks)
  match 'xmlrpc.php',   to: 'traps#fake_xmlrpc', via: %i[get post]
  match 'xmrlpc.php',   to: 'traps#fake_xmlrpc', via: %i[get post]

  # Fingerprint capture (looks like a WP tracking pixel)
  get 'wp-admin/fp.gif', to: 'traps#capture_fingerprint'

  # Fake WordPress admin
  get 'wp-admin',       to: 'traps#fake_admin'
  get 'wp-admin/*path', to: 'traps#fake_admin'

  # Catch-all WordPress paths
  get 'wp-content/*path',   to: 'traps#catch_all'
  get 'wp-includes/*path',  to: 'traps#catch_all'
  get 'wp-json/*path',      to: 'traps#catch_all'

  # Other suspicious paths
  get 'phpmyadmin',          to: 'traps#catch_all'
  get 'phpmyadmin/*path',    to: 'traps#catch_all'
  get 'phpMyAdmin',          to: 'traps#catch_all'
  get 'phpMyAdmin/*path',    to: 'traps#catch_all'
  get 'administrator',       to: 'traps#catch_all'
  get 'administrator/*path', to: 'traps#catch_all'
  get '.env',                to: 'traps#catch_all'
  get '.git/*path',          to: 'traps#catch_all'

  # Catch-all for legacy extensions (must be last)
  constraints(->(req) { PestControl::LegacyHandler.legacy_extension?(req.path) }) do
    match '*path', to: 'traps#catch_all', via: :all
  end

  # Catch-all for any .php file
  constraints(->(req) { req.path.end_with?('.php') }) do
    match '*path', to: 'traps#catch_all', via: :all
  end
end
