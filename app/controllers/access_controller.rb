# Everything that decides whether the Control UI opens on your domain:
#
# - gateway.publicOrigin / gateway.controlUi.allowedOrigins — the browser
#   origin check on the websocket ("origin not allowed").
# - gateway.trustedProxies — without Caddy's address here, any request carrying
#   X-Forwarded-* headers gets a 403 (proxy_attribution_required), including the
#   page's JavaScript: the blank white screen.
class AccessController < ApplicationController
  PROXY_LOG = /unattributable proxy-shaped traffic from \[?([0-9A-Fa-f:.]+[0-9A-Fa-f])\]?/

  def show
    @setting = Setting.instance
    load_gateway_access
  end

  def update
    @setting = Setting.instance
    unless @setting.update(control_ui_url: params[:control_ui_url].to_s.strip)
      load_gateway_access
      return render :show, status: :unprocessable_entity
    end

    respond_with_patch gateway_patch, "Saved. Access settings apply without a restart — reload the Control UI."
  end

  def trust_proxy
    address = params.require(:address).to_s
    return head :unprocessable_entity unless address.match?(/\A[0-9A-Fa-f:.]+(\/\d{1,3})?\z/)

    proxies = Array(ConfigFile.get("gateway.trustedProxies")) | [ address ]
    respond_with_patch({ "gateway" => { "trustedProxies" => proxies } }, "Trusted #{address} as a reverse proxy.")
  end

  private

  def load_gateway_access
    values = %w[gateway.publicOrigin gateway.controlUi.allowedOrigins gateway.trustedProxies]
               .map { |key| Thread.new { ConfigFile.get(key) } }.map(&:value)
    @public_origin, allowed, trusted = values
    @allowed_origins = Array(allowed)
    @trusted_proxies = Array(trusted)
    @observed_proxies = Stack.logs(tail: 5000).output.scan(PROXY_LOG).flatten.uniq - @trusted_proxies
  end

  # The Control UI address becomes gateway.publicOrigin when it's HTTPS (the
  # only scheme OpenClaw accepts there besides localhost). An explicit
  # allowedOrigins list overrides publicOrigin, so the address joins the list
  # whenever there is one.
  def gateway_patch
    origin = origin_of(@setting.control_ui_url)
    https = origin&.start_with?("https://")
    allowed = lines(params[:allowed_origins])
    allowed |= [ origin ] if origin && (allowed.any? || !https)

    {
      "gateway" => {
        "publicOrigin" => https ? origin : nil,
        "controlUi" => { "allowedOrigins" => allowed.presence },
        "trustedProxies" => lines(params[:trusted_proxies]).presence
      }
    }
  end

  def respond_with_patch(changes, notice)
    result = ConfigFile.patch(changes, note: "Before changing access settings in the panel")
    if result.success?
      redirect_to access_path, notice: notice
    else
      redirect_to access_path, alert: "OpenClaw rejected the change: #{result.output.lines.grep_v(/^\[openclaw\] (Debug|Try|Help):/).last(4).join.strip}"
    end
  end

  def origin_of(url)
    uri = URI.parse(url.to_s)
    return unless uri.is_a?(URI::HTTP) && uri.host.present?

    default_port = uri.port == uri.default_port
    "#{uri.scheme}://#{uri.host}#{":#{uri.port}" unless default_port}"
  rescue URI::InvalidURIError
    nil
  end

  def lines(text)
    text.to_s.split(/[\s,]+/).map(&:strip).reject(&:empty?).uniq
  end
end
