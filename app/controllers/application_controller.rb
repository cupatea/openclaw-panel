class ApplicationController < ActionController::Base
  allow_browser versions: :modern

  include AdminAuthentication

  before_action :secure_session_cookie_on_https

  rescue_from Operation::Busy do |error|
    redirect_back_or_to root_path, alert: "#{error.message} Wait for it to finish."
  end

  private

  # Secure cookies only make sense over HTTPS (a domain behind Caddy). Over
  # plain http://nas:3005 on the tailnet the browser would drop them.
  def secure_session_cookie_on_https
    request.session_options[:secure] = request.ssl?
  end

  def start_operation(kind, arguments: [])
    operation = Operation.start!(kind, arguments: arguments)
    redirect_to operation_path(operation)
  end
end
