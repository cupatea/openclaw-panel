# Docker's `restart: unless-stopped` only reacts when the gateway *exits*. A
# gateway that hangs — healthcheck failing, process still alive — stays broken
# until someone restarts it by hand. The watchdog is that someone: once the
# gateway has been unhealthy (or unexpectedly down) for the grace period, it
# queues a restart, at most MAX_RESTARTS times per hour so a gateway that
# can't start isn't hammered forever.
class Watchdog
  INTERVAL = 30.seconds
  MAX_RESTARTS = 3

  class << self
    def start
      return if @thread&.alive?

      watchdog = new
      @thread = Thread.new do
        loop do
          sleep INTERVAL
          Rails.application.executor.wrap { watchdog.tick }
        rescue StandardError => e
          Rails.logger.warn("[Watchdog] #{e.class}: #{e.message}")
        end
      end
    end

    def gave_up?
      Operation.where(trigger: "watchdog", created_at: 1.hour.ago..).count >= MAX_RESTARTS
    end
  end

  attr_reader :bad_since

  def tick(now: Time.current)
    setting = Setting.instance
    return reset unless setting.watchdog_enabled? && Operation.active.none?

    container = Stack.gateway
    return reset unless needs_help?(container)

    @bad_since ||= now
    return if now - bad_since < setting.watchdog_grace_minutes.minutes
    return if self.class.gave_up?
    return if Diagnosis.new(container, Stack.logs(tail: 100).output).waiting_for_lease?

    Operation.start!(container.nil? || container.down? ? "start" : "restart", trigger: "watchdog")
    reset
  rescue Operation::Busy
    reset
  end

  private

  def reset
    @bad_since = nil
  end

  # Down counts only if nobody stopped it on purpose: the newest manual
  # operation being a "stop" means the owner wants it off.
  def needs_help?(container)
    return false if container.nil?
    return true if container.unhealthy?

    container.down? && Operation.where(trigger: "manual").recent.first&.kind != "stop"
  end
end
