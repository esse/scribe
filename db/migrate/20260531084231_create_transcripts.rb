class CreateTranscripts < ActiveRecord::Migration[8.1]
  def change
    create_table :transcripts do |t|
      # One transcript per recording; re-running TranscribeJob upserts this row (SPEC §5 idempotency).
      t.references :recording, null: false, foreign_key: true, index: { unique: true }
      t.string :provider
      t.string :language
      t.text :full_text
      t.jsonb :raw_payload, null: false, default: {}
      t.integer :status, null: false, default: 0

      t.timestamps
    end

    create_table :transcript_segments do |t|
      t.references :transcript, null: false, foreign_key: true
      t.integer :position, null: false
      t.integer :start_ms, null: false
      t.integer :end_ms, null: false
      t.text :text, null: false, default: ""

      t.timestamps
    end

    add_index :transcript_segments, %i[transcript_id position], unique: true
  end
end
