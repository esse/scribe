require "test_helper"

# Ingesting an existing video file (the "use a recording I already have" / CLI
# path). Probing needs ffprobe, so duration assertions are guarded.
class RecordingIngestTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "from_path stores the file, creates an uploaded recording, and enqueues processing" do
    path = Rails.root.join("test/fixtures/files/sample_recording.mp4").to_s

    recording = nil
    assert_enqueued_with(job: TranscribeJob) do
      recording = RecordingIngest.from_path(path)
    end

    assert recording.uploaded?
    assert_equal User.local, recording.user
    assert recording.storage_key.end_with?(".mp4")
    assert Storage.exists?(recording.storage_key)
  end

  test "inline mode runs the chain under the inline adapter and restores it afterward" do
    # The pipeline chains stage-to-stage with perform_later. A one-shot inline
    # run has no worker, so it must execute those under the inline adapter or the
    # pipeline would stall after transcription with jobs stuck on the queue.
    path = Rails.root.join("test/fixtures/files/sample_recording.mp4").to_s
    original = ActiveJob::Base.queue_adapter

    adapter_during_run = nil
    TranscribeJob.define_singleton_method(:perform_now) { |_id| adapter_during_run = ActiveJob::Base.queue_adapter }
    begin
      RecordingIngest.from_path(path, inline: true)
    ensure
      TranscribeJob.singleton_class.send(:remove_method, :perform_now)
    end

    assert_instance_of ActiveJob::QueueAdapters::InlineAdapter, adapter_during_run
    assert_equal original, ActiveJob::Base.queue_adapter
  end

  test "from_path raises for a missing file" do
    assert_raises(RecordingIngest::Error) { RecordingIngest.from_path("/no/such/file.mp4") }
  end

  test "sanitizes odd filenames to a safe extension" do
    assert_equal ".mp4", RecordingIngest.sanitized_extension("clip.mp4")
    assert_equal ".webm", RecordingIngest.sanitized_extension("weird name with spaces")
    assert_equal ".webm", RecordingIngest.sanitized_extension("evil.../../x")
  end
end
