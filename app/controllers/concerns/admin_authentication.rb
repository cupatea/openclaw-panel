module AdminAuthentication
  extend ActiveSupport::Concern

  SESSION_LIFETIME = 30.minutes

  included do
    # Run before CSRF verification so an anonymous mutation consistently gets
    # 401; authenticated mutations still pass through Rails' CSRF protection.
    prepend_before_action :require_admin
    helper_method :admin_authenticated?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_admin, **options
    end
  end

  private

  def admin_authenticated?
    authenticated_at = session[:admin_authenticated_at]
    authenticated_at.present? && Time.at(authenticated_at) > SESSION_LIFETIME.ago
  end

  def require_admin
    return if admin_authenticated?

    reset_session if session[:admin_authenticated_at].present?

    if request.get? || request.head?
      session[:admin_return_to] = request.fullpath
      redirect_to admin_login_path, alert: "Sign in to continue."
    else
      head :unauthorized
    end
  end
end
