class Setting < ApplicationRecord
  has_secure_password :admin_password, validations: false

  validates :admin_password, length: { minimum: 12 }, allow_nil: true
  validates :watchdog_grace_minutes, numericality: { only_integer: true, in: 1..60 }
  validates :control_ui_url, format: { with: %r{\Ahttps?://\S+\z}, allow_blank: true }

  # Singleton — there is only ever one row. Use Setting.instance to access it.
  def self.instance
    first_or_create!
  end

  def admin_password_configured?
    admin_password_digest.present?
  end

  def change_admin_password!(password)
    update!(admin_password: password)
  end
end
