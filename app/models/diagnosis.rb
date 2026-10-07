# Turns the gateway's state and recent logs into plain-language problems, each
# with the one-click fix (an Operation kind) or the page that fixes it.
class Diagnosis
  Finding = Data.define(:title, :detail, :fix, :link) do
    def initialize(title:, detail: nil, fix: nil, link: nil) = super
  end

  # Problems that show up in logs while the gateway otherwise looks fine only
  # count if they're this recent.
  RECENT = 30.minutes
  LEASE_WAIT = /Waiting for (.+?) lease \S+ held by \S+; current lease expires at (\S+?)\.?$/

  attr_reader :container, :log_lines

  def initialize(container, logs)
    @container = container
    @log_lines = logs.to_s.lines.map(&:chomp)
  end

  def findings
    @findings ||= [ *state_findings, *log_findings ].uniq(&:title)
  end

  # A gateway that died mid-maintenance leaves leases behind; the next one
  # waits (unhealthy) until they expire. Restarting then only makes it worse.
  def waiting_for_lease?
    log_lines.last(100).any? { |line| (expiry = lease_expiry(line)) && expiry > Time.current }
  end

  private

  def state_findings
    return [ Finding.new(title: "The gateway container doesn't exist", detail: "Start it to create it from the compose file.", fix: "start") ] if container.nil?

    findings = []
    if container.oom_killed?
      findings << Finding.new(title: "The gateway ran out of memory",
                              detail: "Docker killed it (OOM). Give the NAS/container more memory or remove memory limits.")
    end
    if container.exit_code == 78 && !container.healthy?
      findings << Finding.new(title: "OpenClaw refused to open its data (exit code 78)",
                              detail: "The state database can't be migrated safely — usually because a newer version already migrated it and this one is older. Switch back to the newer version.",
                              link: :updates)
    end
    if container.unhealthy?
      findings << Finding.new(title: "The gateway is running but not answering its health check",
                              detail: container.last_health_output || "It's probably hung. A restart usually brings it back.",
                              fix: "restart")
    end
    findings
  end

  def log_findings
    broken = container.nil? || !container.healthy?
    lines = broken ? log_lines.last(150) : recent_lines

    findings = []
    lines.reverse_each do |line|
      message = line.sub(/\A\S+Z\s+/, "")

      case message
      when /Gateway start blocked: (.*gateway\.mode.*)/
        findings << Finding.new(title: "The gateway refuses to start: gateway.mode isn't set",
                                detail: $1.strip, fix: "fix_gateway_mode")
      when /Gateway start blocked: (.*)/
        findings << Finding.new(title: "The gateway refuses to start", detail: $1.strip, link: :config)
      when /unattributable proxy-shaped traffic from \[?([0-9A-Fa-f:.]+[0-9A-Fa-f])/
        findings << Finding.new(title: "Requests through your reverse proxy (#{$1}) are being refused",
                                detail: "The gateway answers 403 to proxied requests from addresses that aren't in gateway.trustedProxies — including the Control UI's JavaScript, which leaves a blank white page. Trust it on the Access page.",
                                link: :access)
      when /staging file changed during transfer/
        findings << Finding.new(title: "Known OpenClaw bug on this NAS's filesystem",
                                detail: "The pre-migration snapshot fails on hosts without statx/birthtime (openclaw#164876, fixed after 2026.9.8). Pin the previous version until a release with the fix is out.",
                                link: :updates)
      when /openat2.*ENOSYS|ENOSYS.*openat2/
        findings << Finding.new(title: "The NAS kernel is too old for OpenClaw's state lock",
                                detail: "#{message.strip.truncate(200)} — a known issue on older Synology kernels (openclaw#152839). Try another version.",
                                link: :updates)
      when /Config auto-restored from (?:backup|last-known-good)(.*)/
        findings << Finding.new(title: "Your last openclaw.json change was rejected and reverted",
                                detail: "OpenClaw restored the last good config on startup#{$1.strip.presence&.then { |rest| ": #{rest.truncate(250)}" }}. Edit it in the panel — it validates before saving.",
                                link: :config)
      when /attempt to write a readonly database|suspicious ownership/i
        findings << Finding.new(title: "OpenClaw can't write its own files",
                                detail: "#{message.strip.truncate(300)} — files must belong to uid 1000 (node).",
                                fix: "fix_permissions")
      when LEASE_WAIT
        lease = $1
        expires = lease_expiry(message)
        if expires && expires > Time.current
          findings << Finding.new(title: "OpenClaw is waiting for a lock left by a previous run",
                                  detail: "The #{lease} lease belongs to a gateway process that died and expires at #{expires.localtime.strftime("%H:%M:%S")}. It clears itself — restarting in the meantime makes it worse.")
        end
      when /Doctor stopped because a state migration refused to continue/
        findings << Finding.new(title: "Startup checks stopped: a state migration refused to run",
                                detail: "Usually a lock left by a crashed run (it clears within a few minutes) — see the logs for the step that refused.",
                                link: :logs)
      when /memory pressure: level=critical/
        findings << Finding.new(title: "The gateway is running out of memory", detail: message.strip.truncate(300))
      when /EACCES|permission denied/i
        findings << Finding.new(title: "Permission denied on the OpenClaw data folder",
                                detail: "#{message.strip.truncate(300)} — files must belong to uid 1000 (node).",
                                fix: "fix_permissions")
      when /config (?:is )?invalid|invalid config|JSON5 parse failed/i
        findings << Finding.new(title: "openclaw.json is invalid", detail: message.strip.truncate(300), link: :config)
      when /EADDRINUSE/
        findings << Finding.new(title: "A port the gateway needs is already taken",
                                detail: "#{message.strip.truncate(300)} — another container or app on the NAS uses it.")
      when /origin not allowed/i
        findings << Finding.new(title: "The Control UI was opened from an origin the gateway doesn't allow",
                                detail: "Add your domain on the Access page — that's the usual cause of a blank Control UI behind a domain.",
                                link: :access)
      when /pairing required/i
        findings << Finding.new(title: "A browser or device is waiting for pairing approval",
                                detail: "Approve it on the Devices page.", link: :devices)
      when /heap out of memory/i
        findings << Finding.new(title: "The gateway ran out of memory", detail: message.strip.truncate(300))
      end
    end
    findings
  end

  def lease_expiry(line)
    Time.iso8601(LEASE_WAIT.match(line)[2]) if LEASE_WAIT.match?(line)
  rescue ArgumentError
    nil
  end

  def recent_lines
    cutoff = RECENT.ago
    log_lines.select do |line|
      timestamp = line[/\A(\S+Z)\s/, 1]
      timestamp && (Time.iso8601(timestamp) rescue nil)&.>=(cutoff)
    end
  end
end
