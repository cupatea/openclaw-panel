require "shellwords"

# Escape hatch: any `openclaw …` command, run like `docker compose exec -T
# openclaw-gateway node dist/index.js …`. Interactive commands (onboard,
# configure, tui) need a terminal and won't work here.
class ConsoleController < ApplicationController
  PRESETS = [
    [ "Status", "status --all" ],
    [ "Doctor (read-only)", "doctor --lint" ],
    [ "Channels", "channels status --probe" ],
    [ "Models", "models status" ],
    [ "Health", "health" ],
    [ "Security audit", "security audit" ],
    [ "Gateway logs", "logs --limit 200 --plain" ]
  ].freeze

  def show
    @command = params[:command]
    @operations = Operation.where(kind: "cli").recent.limit(15)
  end

  def create
    arguments = Shellwords.split(params[:command].to_s)
    arguments.shift if arguments.first == "openclaw"
    return redirect_to console_path, alert: "Type a command." if arguments.empty?

    start_operation("cli", arguments: arguments)
  rescue ArgumentError => e
    redirect_to console_path(command: params[:command]), alert: "Couldn't parse that: #{e.message}"
  end
end
