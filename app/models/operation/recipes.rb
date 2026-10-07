# What each kind of operation actually runs. Every step is logged as the
# command you'd have typed over SSH, followed by its output.
module Operation::Recipes
  extend ActiveSupport::Concern

  RECIPES = {
    "restart"          => { title: "Restart gateway",            run: :run_restart },
    "start"            => { title: "Start gateway",              run: :run_start },
    "stop"             => { title: "Stop gateway",               run: :run_stop },
    "recreate"         => { title: "Recreate gateway container", run: :run_recreate },
    "update"           => { title: "Update OpenClaw",            run: :run_update },
    "switch_version"   => { title: "Switch OpenClaw version",    run: :run_switch_version },
    "repair"           => { title: "Repair with doctor",         run: :run_repair },
    "fix_gateway_mode" => { title: "Set gateway.mode to local",  run: :run_fix_gateway_mode },
    "fix_permissions"  => { title: "Fix volume permissions",     run: :run_fix_permissions },
    "cli"              => { title: "Command",                    run: :run_cli }
  }.freeze

  def run_restart
    return run_start if Stack.gateway.nil?

    compose("restart", Stack::GATEWAY) && wait_until_healthy
  end

  # `up` (not `restart`) is also what applies .env and compose file changes.
  def run_start
    compose("up", "--detach", Stack::GATEWAY) && wait_until_healthy
  end

  def run_stop
    compose("stop", Stack::GATEWAY)
  end

  def run_recreate
    compose("up", "--detach", "--force-recreate", Stack::GATEWAY) && wait_until_healthy
  end

  # Pulls whatever the compose file points at (`latest`, usually). If the new
  # image doesn't come up healthy, pins the version that was running before.
  def run_update
    previous = Stack.gateway
    log "Running version: #{previous&.version || "unknown"}\n\n"

    return false unless compose("pull", Stack::GATEWAY)

    if previous && previous.raw["Image"] == local_image_id(previous.image)
      log "Already on the newest #{previous.image}. Nothing to do.\n"
      return true
    end

    return false unless compose("up", "--detach", Stack::GATEWAY)
    return report_version(previous&.version) if wait_until_healthy

    previous&.version ? fall_back_to(previous.version) : false
  end

  # arguments: [tag] — a release tag like "2026.9.8", or "latest" to unpin.
  # Pins it via OPENCLAW_IMAGE in .env; puts the old value back on failure.
  def run_switch_version
    tag = arguments.first.to_s
    previous_version = Stack.gateway&.version
    previous_image = EnvFile.entries[Stack::IMAGE_VARIABLE]

    set_image_variable(tag == "latest" ? nil : "#{Stack::IMAGE_REPOSITORY}:#{tag}")
    if compose("pull", Stack::GATEWAY) && compose("up", "--detach", Stack::GATEWAY) && wait_until_healthy
      return report_version(previous_version)
    end

    log "\n#{tag} didn't come up healthy — switching back.\n\n"
    set_image_variable(previous_image)
    compose("up", "--detach", Stack::GATEWAY) && wait_until_healthy
    false
  end

  # The entrypoint already runs `doctor --fix --non-interactive` (safe
  # migrations only) on every start; this applies the full recommended repairs.
  # Never against a live gateway — the two fight over the state database.
  def run_repair
    compose("stop", Stack::GATEWAY) &&
      openclaw("doctor", "--repair", "--yes", running: false) &&
      compose("up", "--detach", Stack::GATEWAY) &&
      wait_until_healthy
  end

  # Stopped first: a crash-looping container is alive for a few seconds at a
  # time, and an `exec` into it would die with it.
  def run_fix_gateway_mode
    compose("stop", Stack::GATEWAY) &&
      openclaw("config", "set", "gateway.mode", "local", running: false) &&
      run_start
  end

  # The gateway runs as `node` (uid 1000). Files created by root — a NAS file
  # manager, a `sudo` command, an older image — make it fail with EACCES.
  def run_fix_permissions
    compose("stop", Stack::GATEWAY) &&
      compose("run", "--rm", "--no-deps", "-T", "--user", "root", "--entrypoint", "chown", Stack::GATEWAY,
              "-R", "1000:1000", "/home/node/.openclaw", "/home/node/.config/openclaw") &&
      compose("up", "--detach", Stack::GATEWAY) &&
      wait_until_healthy
  end

  def run_cli
    openclaw(*arguments)
  end

  private

  def compose(*args)
    run_step Stack.compose(*args), "docker compose #{args.join(" ")}"
  end

  def openclaw(*args, running: Stack.gateway&.running?)
    run_step Stack.cli_argv(*args, running: running), "openclaw #{args.join(" ")}"
  end

  def run_step(argv, display)
    log "$ #{display}\n"
    status = Shell.stream(*argv, timeout: 900) { |text| log text.gsub(Stack::RUN_NOISE, "") }
    log(status.zero? ? "\n" : "(exit code #{status})\n\n")
    status.zero?
  end

  def wait_until_healthy
    Stack.wait_until_healthy { |line| log line }
  end

  def set_image_variable(value)
    EnvFile.update(Stack::IMAGE_VARIABLE => value)
    log(value ? "Set #{Stack::IMAGE_VARIABLE}=#{value} in .env\n\n" : "Removed #{Stack::IMAGE_VARIABLE} from .env (back to the compose default)\n\n")
  end

  def fall_back_to(version)
    unless Stack.version_pinning?
      log "\nThe new version didn't come up healthy. The compose file doesn't use ${#{Stack::IMAGE_VARIABLE}}, so the panel can't pin the previous version.\n"
      return false
    end

    log "\nThe new version didn't come up healthy — pinning #{version}, the version that was running before.\n\n"
    set_image_variable("#{Stack::IMAGE_REPOSITORY}:#{version}")
    compose("pull", Stack::GATEWAY) && compose("up", "--detach", Stack::GATEWAY) && wait_until_healthy
    false
  end

  def report_version(previous_version)
    log "\nVersion: #{previous_version || "unknown"} → #{Stack.gateway&.version || "unknown"}\n"
    true
  end

  def local_image_id(reference)
    Shell.capture("docker", "image", "inspect", reference, "--format", "{{.Id}}", timeout: 15).output.strip
  end
end
