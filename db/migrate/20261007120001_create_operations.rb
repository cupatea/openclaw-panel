class CreateOperations < ActiveRecord::Migration[8.1]
  def change
    create_table :operations do |t|
      t.string   :kind, null: false
      t.json     :arguments, null: false, default: []
      t.string   :status, null: false, default: "queued"
      t.string   :trigger, null: false, default: "manual"
      t.text     :output, null: false, default: ""
      t.datetime :started_at
      t.datetime :finished_at

      t.timestamps
    end

    add_index :operations, :status
    add_index :operations, :created_at
  end
end
