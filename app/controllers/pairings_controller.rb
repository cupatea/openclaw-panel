class PairingsController < ApplicationController
  CHANNEL = /\A[a-z0-9-]+\z/
  CODE = /\A[A-Za-z0-9-]{3,64}\z/

  # The chat channel's bot sends the new contact a code; approving it here is
  # `openclaw pairing approve <channel> <code> --notify`.
  def approve
    channel = params[:channel].to_s.strip.downcase
    code = params[:code].to_s.strip

    unless CHANNEL.match?(channel) && CODE.match?(code)
      return redirect_to devices_path, alert: "Enter the channel and the pairing code the bot sent."
    end

    result = Stack.cli("pairing", "approve", channel, code, "--notify")
    if result.success?
      redirect_to devices_path, notice: "Approved #{channel} code #{code}."
    else
      redirect_to devices_path, alert: result.output.lines.grep_v(/^\[openclaw\] (Debug|Try|Help):/).last(3).join.strip.presence || "Failed."
    end
  end
end
