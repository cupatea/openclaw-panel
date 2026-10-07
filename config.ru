# This file is used by Rack-based servers to start the application.

require_relative "config/environment"

# Web server process only (not rake, runner or console): anything still
# "running" was cut off by the restart, and the watchdog lives here.
begin
  Operation.interrupt_orphans!
  Watchdog.start
rescue ActiveRecord::ActiveRecordError => e
  Rails.logger.warn("[Boot] operations/watchdog not started: #{e.message}")
end

run Rails.application
Rails.application.load_server
