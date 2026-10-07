# A `docker inspect` snapshot of the gateway container.
class Stack::Container
  attr_reader :raw

  def initialize(raw)
    @raw = raw
  end

  def id = raw["Id"].to_s.first(12)
  def name = raw["Name"].to_s.delete_prefix("/")
  def state = raw.dig("State", "Status").to_s
  def health = raw.dig("State", "Health", "Status")
  def restart_count = raw["RestartCount"].to_i
  def exit_code = raw.dig("State", "ExitCode").to_i
  def oom_killed? = raw.dig("State", "OOMKilled") == true
  def error = raw.dig("State", "Error").presence
  def image = raw.dig("Config", "Image").to_s
  def image_id = raw["Image"].to_s.delete_prefix("sha256:").first(12)
  def version = raw.dig("Config", "Labels", "org.opencontainers.image.version")

  def started_at = time(raw.dig("State", "StartedAt"))
  def finished_at = time(raw.dig("State", "FinishedAt"))

  def running? = state == "running"
  def restarting? = state == "restarting"
  def down? = %w[exited dead created].include?(state)

  # Healthy, or running with no healthcheck defined to say otherwise.
  def healthy? = running? && (health.nil? || health == "healthy")
  def unhealthy? = running? && health == "unhealthy"
  def starting? = running? && health == "starting"

  # Docker's restart policy brings a crashing gateway back again and again;
  # between attempts it's "restarting", and right after one it's "starting".
  def crash_looping?
    restarting? || (restart_count >= 3 && !healthy? && started_at.present? && started_at > 2.minutes.ago)
  end

  def uptime = running? && started_at ? Time.current - started_at : nil

  # One of: healthy starting unhealthy crashing stopped — drives the badge colour.
  def condition
    if crash_looping? then "crashing"
    elsif healthy? then "healthy"
    elsif starting? then "starting"
    elsif unhealthy? then "unhealthy"
    else "stopped"
    end
  end

  def summary
    case condition
    when "crashing" then "crash-looping (#{restart_count} restarts)"
    when "stopped" then oom_killed? ? "killed: out of memory" : "#{state} (exit code #{exit_code})"
    else condition
    end
  end

  # Latest healthcheck probe output, e.g. why the gateway is unhealthy.
  def last_health_output
    raw.dig("State", "Health", "Log")&.last&.dig("Output").to_s.strip.presence
  end

  private

  def time(value)
    return if value.blank? || value.start_with?("0001-")

    Time.zone.parse(value)
  rescue ArgumentError
    nil
  end
end
