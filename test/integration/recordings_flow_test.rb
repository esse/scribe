require "test_helper"

# Upload completion: finalize the tus upload and hand off to the editor (SPEC §7.2).
# Local-first — no billing gate. Also covers ingesting an existing video file.
class RecordingsFlowTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @user = User.local
    @recording = @user.recordings.create!(status: :recording)
    @tus_id = "/files/abc123"
    stage_tus_upload(@tus_id)
  end

  test "complete finalizes the upload and hands off to the editor (pipeline starts on apply)" do
    # The pipeline doesn't start at /complete — the editor kicks it off on apply.
    assert_no_enqueued_jobs(only: TranscribeJob) do
      post complete_recording_path(@recording), params: { tus_upload_id: @tus_id }
    end
    assert_response :success
    assert_equal edit_recording_path(@recording), JSON.parse(response.body)["edit_url"]

    @recording.reload
    assert @recording.uploaded?
    assert @recording.editable?
    assert @recording.storage_key.present?
    assert_operator @recording.duration_seconds.to_f, :>, 0
  end

  test "upload ingests an existing video file and starts processing" do
    file = fixture_file_upload("sample_recording.mp4", "video/mp4")

    assert_enqueued_with(job: TranscribeJob) do
      post upload_recordings_path, params: { file: }
    end

    recording = Recording.order(:created_at).last
    assert_redirected_to recording_path(recording)
    assert recording.uploaded?
    assert recording.storage_key.present?
    assert Storage.exists?(recording.storage_key)
  end

  test "upload without a file redirects with an alert" do
    post upload_recordings_path
    assert_redirected_to new_recording_path
  end

  private

  def stage_tus_upload(tus_url)
    uid = tus_url.split("/").last
    path = File.join(Scribe.tus_data_dir, uid)
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, self.class.fixture_video)
  end

  def self.fixture_video
    @fixture_video ||= File.binread(Rails.root.join("test/fixtures/files/sample_recording.mp4"))
  end
end
