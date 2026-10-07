# Device pairing (browsers opening the Control UI, apps, nodes) and chat DM
# pairing codes (e.g. a Telegram user messaging the bot for the first time) —
# the approvals that otherwise mean `openclaw devices approve` over SSH.
class DevicesController < ApplicationController
  REQUEST_ID = /\A[\w.:-]+\z/

  def index
    @container = Stack.gateway
    return unless @container&.running?

    devices = Thread.new { Stack.cli_json("devices", "list", "--json", running: true) }
    @pairings = channel_pairings
    @devices, @devices_result = devices.value
  end

  def approve
    respond_with_cli "Approved.", "devices", "approve", request_id, "--json"
  end

  def reject
    respond_with_cli "Rejected.", "devices", "reject", request_id, "--json"
  end

  private

  def request_id
    params[:request_id].to_s.then { |id| REQUEST_ID.match?(id) ? id : raise(ActionController::BadRequest, "bad request id") }
  end

  def respond_with_cli(notice, *args)
    result = Stack.cli(*args)
    if result.success?
      redirect_to devices_path, notice: notice
    else
      redirect_to devices_path, alert: failure_message(result)
    end
  end

  # Every configured chat channel that supports DM pairing, with its pending
  # codes. Channels without pairing just answer with an error and are skipped.
  def channel_pairings
    status, = Stack.cli_json("channels", "status", "--json", running: true)
    channels = Array(status&.dig("channelOrder")).grep(String)

    channels.map { |channel| Thread.new { Stack.cli_json("pairing", "list", channel, "--json", running: true).first } }
            .filter_map(&:value)
            .select { |data| data.is_a?(Hash) && data["requests"].is_a?(Array) }
  end

  def failure_message(result)
    data = Stack.extract_json(result.output)
    data.is_a?(Hash) && data.dig("error", "message") || result.output.lines.last(3).join.strip.presence || "Failed."
  end
end
