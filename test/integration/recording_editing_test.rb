require "test_helper"

# In-browser editor endpoints: serving the source for playback, persisting the
# keep-segments, and kicking off processing on apply (SPEC §7). These avoid the
# ffmpeg-dependent upload path by seeding an uploaded recording directly.
class RecordingEditingTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @user = User.local
    @recording = @user.recordings.create!(
      status: :uploaded,
      storage_key: "edit/source.webm",
      duration_seconds: 120.0,
      mime: "video/webm"
    )
    Storage.put(@recording.storage_key, StringIO.new("fake-webm-bytes"), content_type: "video/webm")
  end

  test "edit page renders for an editable recording" do
    get edit_recording_path(@recording)
    assert_response :success
    assert_select "[data-controller='video-editor']"
  end

  test "edit page redirects once the recording is no longer editable" do
    @recording.complete!
    get edit_recording_path(@recording)
    assert_redirected_to recording_path(@recording)
  end

  test "source_url returns a signed playback url" do
    get source_url_recording_path(@recording, format: :json)
    assert_response :success
    body = JSON.parse(response.body)
    assert body["url"].present?
    assert_equal "video/webm", body["mime"]
  end

  test "apply_edits persists the keep-segments and enqueues the edit job" do
    assert_enqueued_with(job: ApplyEditsJob, args: [ @recording.id ]) do
      post apply_edits_recording_path(@recording, format: :json),
           params: { segments: [ { start: 5, end: 40 }, { start: 80, end: 110 } ] }
    end
    assert_response :success

    @recording.reload
    assert @recording.editing?
    assert_equal [ [ 5.0, 40.0 ], [ 80.0, 110.0 ] ], @recording.edit_segments
  end

  test "apply_edits with no segments still processes the full recording" do
    assert_enqueued_with(job: ApplyEditsJob, args: [ @recording.id ]) do
      post apply_edits_recording_path(@recording, format: :json), params: { segments: [] }
    end
    assert_response :success
    assert @recording.reload.editing?
  end

  test "apply_edits is rejected once processing has moved on" do
    @recording.transcribing!
    assert_no_enqueued_jobs(only: ApplyEditsJob) do
      post apply_edits_recording_path(@recording, format: :json),
           params: { segments: [ { start: 0, end: 10 } ] }
    end
    assert_response :unprocessable_entity
  end
end
