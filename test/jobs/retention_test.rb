require "test_helper"

# Retention purge + full delete (SPEC §14).
class RetentionTest < ActiveSupport::TestCase
  setup { @user = users(:one) }

  test "purge job removes raw video past the window but keeps the manual" do
    old = build_recording(created_at: 40.days.ago, key: "ret/old/source.mp4")
    Manual.create!(recording: old, title: "Kept", status: :ready)
    recent = build_recording(created_at: 2.days.ago, key: "ret/recent/source.mp4")

    purged = PurgeExpiredRecordingsJob.new.perform(retention_days: 30)

    assert_equal 1, purged
    assert old.reload.raw_video_purged_at.present?
    refute Storage.exists?(old.storage_key), "old raw video deleted"
    assert old.manual.reload.persisted?, "manual kept"

    assert recent.reload.raw_video_purged_at.nil?
    assert Storage.exists?(recent.storage_key), "recent raw video untouched"
  end

  test "purge is idempotent" do
    old = build_recording(created_at: 40.days.ago, key: "ret/idem/source.mp4")
    2.times { PurgeExpiredRecordingsJob.new.perform(retention_days: 30) }
    assert old.reload.raw_video_purged_at.present?
  end

  test "destroy! removes every stored object and the db rows" do
    recording = build_recording(created_at: 1.day.ago, key: "del/source.mp4")
    frame_key = "del/frame.png"
    thumb_key = "del/frame_thumb.png"
    Storage.put(frame_key, StringIO.new("img"), content_type: "image/png")
    Storage.put(thumb_key, StringIO.new("img"), content_type: "image/png")
    recording.frames.create!(timestamp_ms: 0, storage_key: frame_key, thumbnail_storage_key: thumb_key, source: :scene)
    manual = Manual.create!(recording:, title: "Doomed", status: :ready)
    export_key = "del/export.zip"
    Storage.put(export_key, StringIO.new("zip"), content_type: "application/zip")
    manual.exports.create!(format: "markdown", status: :ready, storage_key: export_key)

    RecordingPurge.destroy!(recording)

    [ recording.storage_key, frame_key, thumb_key, export_key ].each do |key|
      refute Storage.exists?(key), "#{key} should be deleted"
    end
    refute Recording.exists?(recording.id)
    assert_equal 0, Frame.where(recording_id: recording.id).count
    assert_equal 0, Manual.where(recording_id: recording.id).count
  end

  private

  def build_recording(created_at:, key:)
    recording = @user.recordings.create!(status: :complete, storage_key: key, duration_seconds: 5.0)
    recording.update_column(:created_at, created_at)
    Storage.put(key, StringIO.new("video-bytes"), content_type: "video/mp4")
    recording
  end
end
