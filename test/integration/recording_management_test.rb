require "test_helper"

# Retry-a-failed-stage and delete endpoints (SPEC §14, §16.7).
class RecordingManagementTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @user = User.local
    @recording = @user.recordings.create!(
      status: :failed, failed_stage: :manual_generation,
      storage_key: "mgmt/source.mp4", duration_seconds: 90.0,
      error_message: "boom"
    )
  end

  test "retry re-enqueues the failed stage's job" do
    assert_enqueued_with(job: GenerateManualJob) do
      post retry_recording_path(@recording), as: :json
    end
    assert_response :ok

    @recording.reload
    assert @recording.uploaded?, "status reset so the job's guards pass"
    assert_nil @recording.failed_stage
    assert_nil @recording.error_message
  end

  test "retry on a non-failed recording is rejected" do
    @recording.update!(status: :complete, failed_stage: nil, error_message: nil)
    post retry_recording_path(@recording), as: :json
    assert_response :unprocessable_entity
  end

  test "delete removes the recording" do
    Storage.put(@recording.storage_key, StringIO.new("v"), content_type: "video/mp4")
    delete recording_path(@recording), as: :json
    assert_response :no_content
    refute Recording.exists?(@recording.id)
    refute Storage.exists?("mgmt/source.mp4")
  end
end
