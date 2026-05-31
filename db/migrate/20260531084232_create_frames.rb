class CreateFrames < ActiveRecord::Migration[8.1]
  def change
    create_table :frames do |t|
      t.references :recording, null: false, foreign_key: true
      t.integer :timestamp_ms, null: false
      t.string :storage_key, null: false
      t.string :thumbnail_storage_key
      t.integer :width
      t.integer :height
      t.integer :source, null: false, default: 0

      t.timestamps
    end

    # Natural key for idempotent extraction / on-demand snapping (SPEC §6, §8.5).
    add_index :frames, %i[recording_id timestamp_ms], unique: true
  end
end
