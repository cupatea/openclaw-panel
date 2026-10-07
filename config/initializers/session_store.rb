# `secure` is decided per request (see ApplicationController#secure_session_cookie_on_https):
# the panel is usually opened as plain http://nas:3005 over the tailnet, where a
# Secure cookie would never be sent back and login would loop forever.
Rails.application.config.session_store :cookie_store,
  key: "_openclaw_panel_session",
  expire_after: 30.minutes,
  httponly: true,
  same_site: :lax
