require "test_helper"

class Stack::ContainerTest < ActiveSupport::TestCase
  test "healthy" do
    assert_equal "healthy", container.condition
    assert container.healthy?
  end

  test "running without a healthcheck counts as healthy" do
    assert container(health: nil).healthy?
  end

  test "restarting is crash-looping" do
    assert_equal "crashing", container(state: "restarting", restarts: 4).condition
  end

  test "many restarts and a fresh start without health is crash-looping" do
    assert_equal "crashing", container(health: "starting", restarts: 5, started: 20.seconds.ago).condition
  end

  test "an old restart count on a healthy gateway is fine" do
    assert_equal "healthy", container(restarts: 5, started: 2.days.ago).condition
  end

  test "stopped summary includes the exit code, or OOM" do
    assert_equal "exited (exit code 1)", container(state: "exited", health: nil, exit_code: 1).summary
    assert_equal "killed: out of memory", container(state: "exited", health: nil, exit_code: 137, oom: true).summary
  end

  test "reads version and image from labels and config" do
    assert_equal "2026.9.8", container.version
    assert_equal "ghcr.io/openclaw/openclaw:latest", container.image
  end
end
