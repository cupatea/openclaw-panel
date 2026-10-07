require "test_helper"

class OperationsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup { sign_in_as_admin }

  test "starts a button operation and shows it" do
    post operations_path, params: { kind: "restart" }
    operation = Operation.last
    assert_redirected_to operation_path(operation)
    assert_equal [ "restart", "manual" ], [ operation.kind, operation.trigger ]
  end

  test "refuses kinds that aren't buttons" do
    post operations_path, params: { kind: "cli" }
    assert_response :unprocessable_entity
    assert_equal 0, Operation.count
  end

  test "switch_version only accepts release tags" do
    post operations_path, params: { kind: "switch_version", version: "2026.9.7" }
    assert_equal [ "2026.9.7" ], Operation.last.arguments

    post operations_path, params: { kind: "switch_version", version: "evil; rm -rf" }
    assert_response :unprocessable_entity
  end

  test "a second operation while one runs is refused politely" do
    Operation.create!(kind: "update", status: "running")
    post operations_path, params: { kind: "restart" }, headers: { "HTTP_REFERER" => root_url }
    assert_redirected_to root_url
    assert_match "still running", flash[:alert]
  end

  test "json view for live output" do
    operation = Operation.create!(kind: "restart", status: "running", output: "hello")
    get operation_path(operation, format: :json)
    assert_equal({ "id" => operation.id, "status" => "running", "output" => "hello", "active" => true }, response.parsed_body)
  end

  test "console starts a cli operation without the leading openclaw" do
    post console_path, params: { command: %(openclaw config set gateway.mode "local") }
    assert_equal [ "config", "set", "gateway.mode", "local" ], Operation.last.arguments
  end
end
