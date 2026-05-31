require "test_helper"

# The editor's apply stage: a full-length edit is a pure pass-through to
# transcription (no ffmpeg), a real trim cuts the source and shortens the
# duration (needs ffmpeg, skipped otherwise), and failures behave like any other
# pipeline stage (mark failed-at-editing).
class ApplyEditsJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = User.local
    @recording = @user.recordings.create!(
      status: :uploaded, storage_key: "edit/src.webm",
      duration_seconds: 60.0, mime: "video/webm"
    )
  end

  test "a full-length edit skips ffmpeg and hands straight to transcription" do
    @recording.update!(edit_segments: [ [ 0.0, 60.0 ] ])
    Storage.put(@recording.storage_key, StringIO.new("bytes"), content_type: "video/webm")

    assert_enqueued_with(job: TranscribeJob, args: [ @recording.id ]) do
      ApplyEditsJob.perform_now(@recording.id)
    end

    @recording.reload
    assert @recording.uploaded?, "back to the pipeline entry state"
    assert_nil @recording.edited_storage_key, "no trimmed copy produced for a no-op edit"
  end

  test "a failed edit records failed-at-editing" do
    @recording.update!(edit_segments: [ [ 0.0, 10.0 ] ])
    # No source object in storage → download fails → permanent stage failure.
    ApplyEditsJob.perform_now(@recording.id)

    @recording.reload
    assert @recording.failed?
    assert_equal "editing", @recording.failed_stage
  end

  test "a real trim cuts the source and shortens the duration" do
    skip "ffmpeg not available" unless ffmpeg_available?

    src_bytes = Dir.mktmpdir do |dir|
      path = File.join(dir, "src.mp4")
      _o, err, st = Open3.capture3(
        Media.ffmpeg_bin, "-y",
        "-f", "lavfi", "-i", "testsrc=duration=6:size=160x120:rate=10",
        "-pix_fmt", "yuv420p", path
      )
      raise err unless st.success?
      File.binread(path)
    end

    @recording.update!(storage_key: "edit/src.mp4", mime: "video/mp4", duration_seconds: 6.0, edit_segments: [ [ 0.0, 2.0 ] ])
    Storage.put(@recording.storage_key, StringIO.new(src_bytes), content_type: "video/mp4")

    perform_enqueued_jobs(only: ApplyEditsJob) do
      ApplyEditsJob.perform_later(@recording.id)
    end

    @recording.reload
    assert @recording.edited_storage_key.present?
    assert Storage.exists?(@recording.edited_storage_key)
    assert_operator @recording.duration_seconds, :<, 5.0
    assert_equal @recording.edited_storage_key, @recording.processing_storage_key
  end

  private

  def ffmpeg_available?
    system("#{Media.ffmpeg_bin} -version", out: File::NULL, err: File::NULL)
  end
end
