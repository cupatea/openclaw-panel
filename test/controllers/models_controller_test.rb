require "test_helper"

class ModelsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    sign_in_as_admin
    @calls = []
    stub_method(Stack, :cli) do |*args, input: nil, **|
      @calls << { args: args, input: input }
      Shell::Result.new(argv: args, output: "Auth profile: x", exit_status: 0)
    end
  end

  test "a key goes to the CLI on stdin, never in argv, then the gateway restarts" do
    post models_path, params: { provider: "anthropic", profile_id: "anthropic:default", kind: "api_key", secret: "sk-ant-secret" }

    call = @calls.last
    assert_equal %w[models auth paste-api-key --provider anthropic --profile-id anthropic:default], call[:args]
    assert_equal "sk-ant-secret\n", call[:input]
    assert_not_includes call[:args].join(" "), "sk-ant-secret"
    assert_equal "restart", Operation.last.kind
    assert_redirected_to operation_path(Operation.last)
  end

  test "tokens use paste-token and the default profile id" do
    post models_path, params: { provider: "anthropic", profile_id: "", kind: "token", secret: "tok" }
    assert_equal %w[models auth paste-token --provider anthropic], @calls.last[:args]
  end

  test "invalid input runs nothing" do
    post models_path, params: { provider: "anthropic; rm", secret: "x" }
    post models_path, params: { provider: "anthropic", profile_id: "no-colon", secret: "x" }
    post models_path, params: { provider: "anthropic", secret: "" }
    assert_empty @calls
    assert_equal 0, Operation.count
  end

  test "a failed save shows the CLI's reason and doesn't restart" do
    stub_method(Stack, :cli) { |*args, **| Shell::Result.new(argv: args, output: "Expected token starting with sk-ant-\n", exit_status: 1) }
    post models_path, params: { provider: "anthropic", kind: "token", secret: "bad" }
    assert_redirected_to models_path
    assert_match "Expected token", flash[:alert]
    assert_equal 0, Operation.count
  end

  test "removing a profile with dots and @ in its id" do
    delete model_profile_path("anthropic:me@example.com")
    assert_equal [ "models", "auth", "logout", "anthropic:me@example.com", "--yes" ], @calls.last[:args]
    assert_redirected_to models_path
  end
end
