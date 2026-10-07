# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_07_120002) do
  create_table "config_revisions", force: :cascade do |t|
    t.text "content", null: false
    t.string "note", default: "", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "operations", force: :cascade do |t|
    t.string "kind", null: false
    t.json "arguments", default: [], null: false
    t.string "status", default: "queued", null: false
    t.string "trigger", default: "manual", null: false
    t.text "output", default: "", null: false
    t.datetime "started_at"
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_operations_on_created_at"
    t.index ["status"], name: "index_operations_on_status"
  end

  create_table "settings", force: :cascade do |t|
    t.string "admin_password_digest"
    t.boolean "watchdog_enabled", default: true, null: false
    t.integer "watchdog_grace_minutes", default: 3, null: false
    t.string "control_ui_url", default: "", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end
end
