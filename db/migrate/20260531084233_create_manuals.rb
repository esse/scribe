class CreateManuals < ActiveRecord::Migration[8.1]
  def change
    create_table :manuals do |t|
      t.references :recording, null: false, foreign_key: true, index: { unique: true }
      t.string :title
      t.text :summary
      t.integer :status, null: false, default: 0
      t.string :model
      t.datetime :generated_at

      t.timestamps
    end

    create_table :manual_steps do |t|
      t.references :manual, null: false, foreign_key: true
      t.integer :position, null: false
      t.string :title
      t.text :body_markdown
      t.references :frame, null: true, foreign_key: true
      t.integer :source_start_ms
      t.integer :source_end_ms

      t.timestamps
    end

    add_index :manual_steps, %i[manual_id position]
  end
end
