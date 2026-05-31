require "test_helper"

# End-to-end pipeline with a short fixture recording (SPEC §15). STT and the LLM
# are stubbed (the configured defaults), but audio extraction and scene-detected
# frame extraction run real ffmpeg, and storage is the on-disk adapter.
class PipelineTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = User.local
    @recording = @user.recordings.create!(
      status: :uploaded,
      storage_key: "test/pipeline/source.mp4",
      duration_seconds: 4.0,
      scene_threshold: 0.4
    )
    Storage.put(@recording.storage_key, StringIO.new(fixture_video_bytes), content_type: "video/mp4")
  end

  test "runs transcription → frames → manual, completes, and writes result files" do
    perform_enqueued_jobs do
      TranscribeJob.perform_later(@recording.id)
    end

    @recording.reload
    assert @recording.complete?, "recording reached complete (was #{@recording.status}, err=#{@recording.error_message})"

    # Transcript with timestamped segments (SPEC §8.3).
    assert @recording.transcript.ready?
    assert_operator @recording.transcript.segments.count, :>=, 1
    assert @recording.transcript.segments.all? { |s| s.end_ms >= s.start_ms }

    # Scene/fallback frames extracted and stored (SPEC §8.4).
    assert_operator @recording.frames.count, :>=, 1
    assert @recording.frames.all? { |f| Storage.exists?(f.storage_key) }

    # Structured manual persisted, every step linked to a real frame (SPEC §8.5).
    manual = @recording.manual
    assert manual.ready?
    assert manual.title.present?
    assert_operator manual.steps.count, :>=, 1
    assert manual.steps.all? { |s| s.frame_id.present? }, "each step references a snapped frame"

    # Local-first: results are also written out as plain files under the data dir.
    base = "recordings/#{@recording.id}/results"
    assert Storage.exists?("#{base}/manual.json"), "manual.json written"
    assert Storage.exists?("#{base}/manual.md"), "manual.md written"
    assert Storage.exists?("#{base}/manual.html"), "manual.html written"
  end

  test "a stage failure marks the recording failed" do
    # Corrupt the source so audio extraction fails.
    Storage.put(@recording.storage_key, StringIO.new("not a real video"), content_type: "video/mp4")

    perform_enqueued_jobs do
      TranscribeJob.perform_later(@recording.id)
    end

    @recording.reload
    assert @recording.failed?
    assert_equal "transcription", @recording.failed_stage
    assert @recording.error_message.present?
  end

  private

  # A small committed fixture (2s, 160x120). Read rather than generated at runtime
  # so parallel test workers don't all spawn ffmpeg encodes at once.
  def fixture_video_bytes
    File.binread(Rails.root.join("test/fixtures/files/sample_recording.mp4"))
  end
end
