class AddEditingToRecordings < ActiveRecord::Migration[8.1]
  def change
    # In-browser editor support. The browser sends a non-destructive edit
    # decision list (keep-segments); the apply-edits job cuts the video with
    # ffmpeg and stores the result separately so the original source can still
    # be re-edited or purged independently.
    add_column :recordings, :edit_segments, :jsonb
    add_column :recordings, :edited_storage_key, :string
  end
end
