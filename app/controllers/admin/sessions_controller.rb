module Admin
  class SessionsController < ApplicationController
    allow_unauthenticated_access only: %i[new create]

    rate_limit to: 5, within: 1.minute, only: :create,
               with: -> { redirect_to admin_login_path, alert: "Too many attempts. Try again in a minute." }

    def new
      redirect_to root_path if admin_authenticated?
      @setting = Setting.instance
    end

    def create
      @setting = Setting.instance

      if @setting.admin_password_configured?
        authenticate
      else
        create_password
      end
    end

    def destroy
      reset_session
      redirect_to admin_login_path, notice: "Signed out."
    end

    private

    def authenticate
      if @setting.authenticate_admin_password(params[:password])
        start_session("Signed in.")
      else
        flash.now[:alert] = "Incorrect password."
        render :new, status: :unprocessable_entity
      end
    end

    def create_password
      @setting.admin_password = params[:password]

      if params[:password] != params[:password_confirmation]
        @setting.errors.add(:admin_password_confirmation, "doesn't match password")
        render :new, status: :unprocessable_entity
      elsif @setting.save
        start_session("Admin password created.")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def start_session(notice)
      return_to = session[:admin_return_to]
      reset_session
      session[:admin_authenticated_at] = Time.current.to_i
      redirect_to safe_return_to(return_to), notice: notice
    end

    def safe_return_to(path)
      path.to_s.start_with?("/") && !path.to_s.start_with?("//") ? path : root_path
    end
  end
end
