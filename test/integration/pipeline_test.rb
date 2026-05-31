require "test_helper"

# End-to-end pipeline with a short fixture recording (SPEC §15). STT and Claude
# are stubbed (the configured defaults), but audio extraction and scene-detected
# frame extraction run real ffmpeg, and storage is the on-disk adapter.
class PipelineTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
    @recording = @user.recordings.create!(
      status: :uploaded,
      storage_key: "test/pipeline/source.mp4",
      duration_seconds: 4.0,
      scene_threshold: 0.4
    )
    Storage.put(@recording.storage_key, StringIO.new(fixture_video_bytes), content_type: "video/mp4")

    Credits::Ledger.grant_purchase!(user: @user, credits: 100, stripe_session_id: "cs_pipeline")
    @hold = Credits::Ledger.hold!(user: @user, amount: Credits::Meter.estimate_for(@recording), reference: @recording)
  end

  test "runs transcription → frames → manual and completes" do
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

    # Hold settled on success (SPEC §13.3).
    assert @hold.reload.settled?
    assert_equal 99, @user.available_credits, "1 credit/minute on a 4s clip → 1 credit settled"
  end

  test "a stage failure marks the recording failed and voids the hold" do
    # Corrupt the source so audio extraction fails.
    Storage.put(@recording.storage_key, StringIO.new("not a real video"), content_type: "video/mp4")

    perform_enqueued_jobs do
      TranscribeJob.perform_later(@recording.id)
    end

    @recording.reload
    assert @recording.failed?
    assert_equal "transcription", @recording.failed_stage
    assert @recording.error_message.present?
    assert @hold.reload.void?, "hold voided on failure"
    assert_equal 100, @user.available_credits, "credits returned to the user"
  end

  private

  # Build a tiny real video once and cache the bytes for the suite.
  def fixture_video_bytes
    @@fixture_video_bytes ||= begin
      Dir.mktmpdir do |dir|
        out = File.join(dir, "fixture.mp4")
        cmd = [
          Media.ffmpeg_bin, "-y",
          "-f", "lavfi", "-i", "testsrc=duration=4:size=320x240:rate=10",
          "-f", "lavfi", "-i", "sine=frequency=440:duration=4",
          "-pix_fmt", "yuv420p", "-shortest", out
        ]
        _o, err, status = Open3.capture3(*cmd)
        raise "fixture ffmpeg failed: #{err}" unless status.success?

        File.binread(out)
      end
    end
  end
end
