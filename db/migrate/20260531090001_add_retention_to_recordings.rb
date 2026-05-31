class AddRetentionToRecordings < ActiveRecord::Migration[8.1]
  def change
    # When the raw video was auto-purged after the retention window; the manual
    # and frames persist (SPEC §14).
    add_column :recordings, :raw_video_purged_at, :datetime
  end
end
