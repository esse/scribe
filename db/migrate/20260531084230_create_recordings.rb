class CreateRecordings < ActiveRecord::Migration[8.1]
  def change
    create_table :recordings do |t|
      t.references :user, null: false, foreign_key: true
      # Pipeline state machine (SPEC §8.1).
      t.integer :status, null: false, default: 0
      t.string :tus_upload_id
      t.string :storage_key
      t.string :mime
      t.float :duration_seconds
      t.float :scene_threshold, null: false, default: 0.4
      t.string :error_message
      t.integer :failed_stage

      t.timestamps
    end

    add_index :recordings, :tus_upload_id, unique: true, where: "tus_upload_id IS NOT NULL"
    add_index :recordings, %i[user_id status]
  end
end
