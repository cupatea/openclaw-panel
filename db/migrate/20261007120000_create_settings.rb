class CreateSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :settings do |t|
      t.string  :admin_password_digest
      t.boolean :watchdog_enabled, null: false, default: true
      t.integer :watchdog_grace_minutes, null: false, default: 5
      t.string  :control_ui_url, null: false, default: ""

      t.timestamps
    end
  end
end
