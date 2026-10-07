class CreateConfigRevisions < ActiveRecord::Migration[8.1]
  def change
    create_table :config_revisions do |t|
      t.text   :content, null: false
      t.string :note, null: false, default: ""

      t.timestamps
    end
  end
end
