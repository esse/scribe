class CreateExports < ActiveRecord::Migration[8.1]
  def change
    create_table :exports do |t|
      t.references :manual, null: false, foreign_key: true
      t.string :format, null: false
      t.integer :status, null: false, default: 0
      t.string :storage_key
      t.bigint :file_size
      t.string :error_message

      t.timestamps
    end

    add_index :exports, %i[manual_id format]
  end
end
