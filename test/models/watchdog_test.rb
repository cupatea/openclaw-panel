require "test_helper"

class WatchdogTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @watchdog = Watchdog.new
    Setting.instance.update!(watchdog_enabled: true, watchdog_grace_minutes: 3)
    stub_method(Stack, :logs, Shell::Result.new(argv: [], output: "", exit_status: 0))
  end

  test "restarts an unhealthy gateway after the grace period" do
    stub_method(Stack, :gateway, container(health: "unhealthy"))
    now = Time.current

    @watchdog.tick(now: now)
    @watchdog.tick(now: now + 2.minutes)
    assert_equal 0, Operation.count

    @watchdog.tick(now: now + 3.minutes)
    assert_equal [ [ "restart", "watchdog" ] ], Operation.pluck(:kind, :trigger)
  end

  test "waits while the gateway is blocked on a stale lease" do
    stub_method(Stack, :gateway, container(health: "unhealthy"))
    line = "#{Time.current.utc.iso8601(9)} [state/lease] Waiting for plugin lifecycle lease core:plugin-lifecycle/global held by fc70; current lease expires at #{2.minutes.from_now.utc.iso8601(3)}.\n"
    stub_method(Stack, :logs, Shell::Result.new(argv: [], output: line, exit_status: 0))

    @watchdog.tick(now: 10.minutes.ago)
    @watchdog.tick(now: Time.current)
    assert_equal 0, Operation.count
  end

  test "recovering resets the clock" do
    now = Time.current
    stub_method(Stack, :gateway, container(health: "unhealthy"))
    @watchdog.tick(now: now)
    stub_method(Stack, :gateway, container)
    @watchdog.tick(now: now + 1.minute)

    assert_nil @watchdog.bad_since
  end

  test "starts a gateway that stopped on its own" do
    stub_method(Stack, :gateway, container(state: "exited", health: nil, exit_code: 1))
    @watchdog.tick(now: 10.minutes.ago)
    @watchdog.tick(now: Time.current)
    assert_equal "start", Operation.last.kind
  end

  test "leaves a gateway alone that you stopped" do
    Operation.create!(kind: "stop", status: "succeeded")
    stub_method(Stack, :gateway, container(state: "exited", health: nil))
    @watchdog.tick(now: 10.minutes.ago)
    @watchdog.tick(now: Time.current)
    assert_equal [ "stop" ], Operation.pluck(:kind)
  end

  test "gives up after a few restarts an hour" do
    Watchdog::MAX_RESTARTS.times { Operation.create!(kind: "restart", trigger: "watchdog", status: "failed") }
    stub_method(Stack, :gateway, container(health: "unhealthy"))
    @watchdog.tick(now: 10.minutes.ago)
    @watchdog.tick(now: Time.current)
    assert_equal Watchdog::MAX_RESTARTS, Operation.count
  end

  test "does nothing when disabled or while another operation runs" do
    stub_method(Stack, :gateway, container(health: "unhealthy"))
    Setting.instance.update!(watchdog_enabled: false)
    @watchdog.tick(now: 10.minutes.ago)
    @watchdog.tick(now: Time.current)
    assert_equal 0, Operation.count
  end
end
