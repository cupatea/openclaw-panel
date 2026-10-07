# The OpenClaw docker-compose project the panel manages.
#
# The panel sees the project folder at OPENCLAW_DIR (bind-mounted, /openclaw in
# the image), but compose resolves `./drive`-style volume paths against the
# project directory and hands them to the *host's* Docker daemon. So compose
# runs with --project-directory set to the folder's real host path, discovered
# from this container's own mounts. Containers end up identical to what
# `docker compose up -d` in that folder over SSH would create.
module Stack
  GATEWAY = ENV.fetch("OPENCLAW_GATEWAY_SERVICE", "openclaw-gateway")
  CLI = %w[node dist/index.js].freeze
  IMAGE_VARIABLE = "OPENCLAW_IMAGE"
  IMAGE_REPOSITORY = ENV.fetch("OPENCLAW_IMAGE_REPOSITORY", "ghcr.io/openclaw/openclaw")
  COMPOSE_FILES = %w[docker-compose.yaml docker-compose.yml compose.yaml compose.yml].freeze

  # `compose run` chatter about the throwaway container — noise in the UI.
  RUN_NOISE = /^\s*Container \S+-run-\h+\s+\S+\s*$\n?/

  class << self
    def dir
      ENV.fetch("OPENCLAW_DIR") { Rails.root.parent.to_s }
    end

    def host_dir
      @host_dir ||= ENV["OPENCLAW_HOST_DIR"].presence || own_mount_source(dir) || dir
    end

    def compose_file
      COMPOSE_FILES.map { |name| File.join(dir, name) }.find { |path| File.exist?(path) } ||
        File.join(dir, COMPOSE_FILES.first)
    end

    def env_file = File.join(dir, ".env")

    # Versions are pinned through OPENCLAW_IMAGE in .env, which only works if
    # the compose file reads it: `image: ${OPENCLAW_IMAGE:-…:latest}`.
    def version_pinning?
      EnvFile.referenced_keys.include?(IMAGE_VARIABLE)
    end

    def compose(*args)
      argv = [ "docker", "compose", "--project-directory", host_dir, "--file", compose_file ]
      argv += [ "--env-file", env_file ] if File.exist?(env_file)
      argv + args.flatten
    end

    # The gateway container as Docker sees it right now; nil if it was never created.
    def gateway
      id = Shell.capture(*compose("ps", "--all", "--quiet", GATEWAY), timeout: 15).output.lines.first&.strip
      return if id.blank?

      inspected = Shell.capture("docker", "inspect", id, timeout: 15)
      return unless inspected.success?

      Container.new(JSON.parse(inspected.output).first)
    rescue JSON::ParserError
      nil
    end

    def logs(tail: 300)
      Shell.capture(*compose("logs", "--no-color", "--no-log-prefix", "--timestamps", "--tail", tail.to_s, GATEWAY), timeout: 20)
    end

    # argv for an `openclaw ...` CLI call. Uses `exec` while the gateway runs
    # (same network namespace, so RPC commands reach it on 127.0.0.1), and a
    # throwaway `run` container otherwise — e.g. to repair a crash-looping one.
    def cli_argv(*args, running: gateway&.running?, env: {})
      env_flags = env.flat_map { |key, value| [ "--env", "#{key}=#{value}" ] }

      if running
        compose("exec", "-T", *env_flags, GATEWAY, *CLI, *args)
      else
        compose("run", "--rm", "--no-deps", "-T", *env_flags, GATEWAY, *CLI, *args)
      end
    end

    def cli(*args, timeout: 60, **options)
      result = Shell.capture(*cli_argv(*args, **options), timeout: timeout)
      result.with(output: result.output.gsub(RUN_NOISE, ""))
    end

    # Runs a `--json` CLI command. Returns [parsed JSON or nil, Shell::Result].
    def cli_json(*args, **options)
      result = cli(*args, **options)
      [ extract_json(result.output), result ]
    end

    # Polls Docker until the gateway reports healthy. Yields progress lines.
    # Gives up early if it keeps crashing: Docker's restart count only grows
    # between our polls when the process died and was brought back.
    def wait_until_healthy(timeout: 300, interval: 3)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      initial_restarts = nil

      loop do
        container = gateway
        elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round
        initial_restarts ||= container&.restart_count
        restarts = container ? container.restart_count - initial_restarts : 0

        if container.nil?
          yield "Gateway container doesn't exist.\n"
          return false
        elsif container.healthy?
          yield "Gateway is #{container.health ? "healthy" : "running"} (#{elapsed}s).\n"
          return true
        elsif container.down?
          yield "Gateway stopped: #{container.summary}.\n"
          return false
        elsif restarts >= 2
          yield "Gateway keeps crashing (#{restarts} restarts in #{elapsed}s). Check the status page and logs.\n"
          return false
        elsif elapsed >= timeout
          yield "Still not healthy after #{elapsed}s (#{container.health || container.state}). Check the status page and logs.\n"
          return false
        end

        yield "Waiting… #{container.restarting? ? "restarting" : container.health || container.state} (#{elapsed}s)\n" if (elapsed % 15) < interval
        sleep interval
      end
    end

    # CLI output mixes stdout and stderr, and failures append "[openclaw] …"
    # lines after the JSON, so pick the JSON document out of the text.
    def extract_json(text)
      start = text.index(/^[\[{]/) or return

      first_line = text[start..].lines.first
      begin
        return JSON.parse(first_line)
      rescue JSON::ParserError
      end

      closers = []
      text.scan(/^[\]}][ \t]*$/) { closers << Regexp.last_match.end(0) }
      closers.select { |stop| stop > start }.reverse_each do |stop|
        return JSON.parse(text[start...stop])
      rescue JSON::ParserError
        next
      end
      nil
    end

    private

    def own_mount_source(path)
      return unless File.exist?("/.dockerenv") && ENV["HOSTNAME"].present?

      result = Shell.capture("docker", "inspect", ENV["HOSTNAME"], "--format", "{{json .Mounts}}", timeout: 10)
      return unless result.success?

      JSON.parse(result.output).find { |mount| mount["Destination"] == path.chomp("/") }&.dig("Source")
    rescue JSON::ParserError
      nil
    end
  end
end
