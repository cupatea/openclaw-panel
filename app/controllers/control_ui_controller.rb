# "Open Control UI": asks the gateway for a single-use owner bootstrap link
# (`openclaw dashboard --json`, valid 10 minutes) and sends the browser to it
# on your domain. That browser gets its own admin device credential — no token
# to paste and no pairing request to approve.
class ControlUiController < ApplicationController
  def create
    address = Setting.instance.control_ui_url.presence
    return redirect_to access_path, alert: "Set the Control UI address first." unless address

    data, result = Stack.cli_json("dashboard", "--json", "--no-open")
    fragment = data.is_a?(Hash) && data["browserUrl"].to_s.split("#", 2).second
    unless fragment
      return redirect_to root_path, alert: "The gateway didn't return a sign-in link: #{result.output.lines.last(2).join.strip}"
    end

    query = URI.decode_www_form(fragment).to_h
    query["gatewayUrl"] = address.sub(%r{\Ahttp}, "ws").sub(%r{\A(wss?://[^/]+).*\z}, '\1')
    redirect_to "#{address.split("#").first}##{URI.encode_www_form(query)}", allow_other_host: true
  end
end
