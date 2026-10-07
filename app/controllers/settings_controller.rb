class SettingsController < ApplicationController
  def show
    @setting = Setting.instance
  end

  def update
    @setting = Setting.instance
    @setting.assign_attributes(params.expect(setting: [ :watchdog_enabled, :watchdog_grace_minutes ]))

    if params[:new_password].present? && !change_password
      return render :show, status: :unprocessable_entity
    end

    if @setting.save
      redirect_to setting_path, notice: "Settings saved."
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def change_password
    if !@setting.authenticate_admin_password(params[:current_password].to_s)
      @setting.errors.add(:base, "Current password is incorrect")
    elsif params[:new_password] != params[:new_password_confirmation]
      @setting.errors.add(:base, "New passwords don't match")
    else
      @setting.admin_password = params[:new_password]
    end
    @setting.errors.empty?
  end
end
