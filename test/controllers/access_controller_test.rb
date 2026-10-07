require "test_helper"

class AccessControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as_admin
    @patches = []
    stub_method(ConfigFile, :patch) do |changes, note:|
      @patches << changes
      Shell::Result.new(argv: [], output: "Applied", exit_status: 0)
    end
  end

  test "an https address becomes publicOrigin and allowedOrigins is dropped" do
    patch access_path, params: { control_ui_url: "https://claw.example.com/", allowed_origins: "", trusted_proxies: "172.18.0.1" }

    assert_redirected_to access_path
    assert_equal({ "publicOrigin" => "https://claw.example.com", "controlUi" => { "allowedOrigins" => nil },
                   "trustedProxies" => [ "172.18.0.1" ] }, @patches.last["gateway"])
    assert_equal "https://claw.example.com/", Setting.instance.control_ui_url
  end

  test "an explicit origin list keeps the address in it" do
    patch access_path, params: { control_ui_url: "https://claw.example.com", allowed_origins: "http://nas.ts.net:18789\n", trusted_proxies: "" }
    assert_equal [ "http://nas.ts.net:18789", "https://claw.example.com" ], @patches.last.dig("gateway", "controlUi", "allowedOrigins")
    assert_nil @patches.last.dig("gateway", "trustedProxies")
  end

  test "an http address can't be publicOrigin, so it goes into the list" do
    patch access_path, params: { control_ui_url: "http://nas.tailnet.ts.net:18789", allowed_origins: "", trusted_proxies: "" }
    assert_nil @patches.last.dig("gateway", "publicOrigin")
    assert_equal [ "http://nas.tailnet.ts.net:18789" ], @patches.last.dig("gateway", "controlUi", "allowedOrigins")
  end

  test "trusting a proxy appends it" do
    stub_method(ConfigFile, :get, [ "10.0.0.1" ])
    post trust_proxy_access_path, params: { address: "172.18.0.1" }
    assert_equal [ "10.0.0.1", "172.18.0.1" ], @patches.last.dig("gateway", "trustedProxies")
  end

  test "trusting garbage is refused" do
    post trust_proxy_access_path, params: { address: "172.18.0.1; rm" }
    assert_response :unprocessable_entity
    assert_empty @patches
  end
end
