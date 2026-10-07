require "test_helper"

class OperationTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "start! queues a job" do
    assert_enqueued_with(job: OperationJob) { Operation.start!("restart") }
    assert_equal "queued", Operation.last.status
  end

  test "only one operation at a time" do
    Operation.create!(kind: "update", status: "running")
    error = assert_raises(Operation::Busy) { Operation.start!("restart") }
    assert_match "Update OpenClaw", error.message
  end

  test "rejects unknown kinds" do
    assert_raises(ActiveRecord::RecordInvalid) { Operation.start!("rm -rf") }
  end

  test "perform runs the recipe's commands and records output" do
    commands = []
    stub_method(Shell, :stream) do |*argv, **, &block|
      commands << argv
      block.call("ok\n")
      0
    end
    stub_method(Stack, :gateway, container)
    stub_method(Stack, :wait_until_healthy) { |**, &block| block.call("Gateway is healthy (1s).\n"); true }

    operation = Operation.create!(kind: "restart")
    operation.perform

    assert_equal "succeeded", operation.reload.status
    assert_equal %w[restart openclaw-gateway], commands.first.last(2)
    assert_includes operation.output, "$ docker compose restart openclaw-gateway"
    assert_includes operation.output, "Gateway is healthy"
  end

  test "a failing step fails the operation and stops the recipe" do
    commands = []
    stub_method(Shell, :stream) { |*argv, **, &block| commands << argv; block.call("boom\n"); 1 }
    stub_method(Stack, :gateway, container)

    operation = Operation.create!(kind: "repair")
    operation.perform

    assert_equal "failed", operation.reload.status
    assert_equal 1, commands.size, "doctor must not run when stopping the gateway failed"
    assert_includes operation.output, "(exit code 1)"
  end

  test "cli operations run openclaw with the given arguments" do
    stub_method(Shell, :stream) { |*argv, **, &block| block.call(argv.last(3).join(" ") + "\n"); 0 }
    stub_method(Stack, :gateway, container)

    operation = Operation.create!(kind: "cli", arguments: [ "config", "get", "gateway.mode" ])
    operation.perform

    assert_equal "openclaw config get gateway.mode", operation.title
    assert_includes operation.output, "config get gateway.mode"
  end

  test "orphaned operations are marked interrupted" do
    operation = Operation.create!(kind: "restart", status: "running")
    Operation.interrupt_orphans!
    assert_equal "interrupted", operation.reload.status
  end
end
