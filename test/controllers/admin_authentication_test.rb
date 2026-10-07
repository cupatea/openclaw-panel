require "test_helper"

class AdminAuthenticationTest < ActionDispatch::IntegrationTest
  setup do
    Setting.instance.change_admin_password!(ADMIN_PASSWORD)
  end

  test "every page needs a session" do
    [ root_path, logs_path, devices_path, config_path, access_path, updates_path,
      environment_path, console_path, operations_path, setting_path, diagnostics_path ].each do |path|
      get path
      assert_redirected_to admin_login_path, "#{path} should require sign in"
    end
  end

  test "every unauthenticated mutation is rejected" do
    requests = [
      -> { post operations_path, params: { kind: "restart" } },
      -> { post console_path, params: { command: "status" } },
      -> { patch config_path, params: { content: "{}" } },
      -> { patch access_path, params: { control_ui_url: "https://x.example" } },
      -> { post trust_proxy_access_path, params: { address: "172.18.0.1" } },
      -> { patch environment_path, params: { new_key: "A", new_value: "b" } },
      -> { post approve_device_path("abc") },
      -> { post approve_pairing_path, params: { channel: "telegram", code: "ABC123" } },
      -> { post control_ui_path },
      -> { patch setting_path, params: { setting: { watchdog_enabled: "0" } } }
    ]
    requests.each do |request|
      request.call
      assert_response :unauthorized
    end
    assert_equal 0, Operation.count
  end

  test "login creates a session that authorizes later requests" do
    get setting_path
    post admin_login_path, params: { password: ADMIN_PASSWORD }
    assert_redirected_to setting_path
    get setting_path
    assert_response :success
  end

  test "first login creates the admin password" do
    Setting.instance.update_column(:admin_password_digest, nil)
    get admin_login_path
    assert_select "h1", "Create admin password"

    post admin_login_path, params: { password: ADMIN_PASSWORD, password_confirmation: ADMIN_PASSWORD }
    assert_response :redirect
    assert Setting.instance.reload.authenticate_admin_password(ADMIN_PASSWORD)
  end

  test "invalid login is rejected and rate limited" do
    5.times do
      post admin_login_path, params: { password: "wrong" }
      assert_response :unprocessable_entity
    end
    post admin_login_path, params: { password: "wrong" }
    assert_redirected_to admin_login_path
  end

  test "session cookie is Secure over HTTPS only" do
    post admin_login_path, params: { password: ADMIN_PASSWORD }
    assert_no_match(/;\s*secure/i, response.headers["set-cookie"].to_s)

    reset!
    https!
    post admin_login_path, params: { password: ADMIN_PASSWORD }
    assert_match(/;\s*secure/i, response.headers["set-cookie"].to_s)
  end

  test "sign out ends the session" do
    sign_in_as_admin
    delete admin_logout_path
    get setting_path
    assert_redirected_to admin_login_path
  end
end
