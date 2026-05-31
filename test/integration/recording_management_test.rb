require "test_helper"

# Retry-a-failed-stage and delete endpoints (SPEC §14, §16.7).
class RecordingManagementTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
    sign_in_as(@user)
    @recording = @user.recordings.create!(
      status: :failed, failed_stage: :manual_generation,
      storage_key: "mgmt/source.mp4", duration_seconds: 90.0,
      error_message: "boom"
    )
  end

  test "retry re-reserves credits and re-enqueues the failed stage's job" do
    Credits::Ledger.grant_purchase!(user: @user, credits: 10, stripe_session_id: "cs_mgmt")

    assert_enqueued_with(job: GenerateManualJob) do
      post retry_recording_path(@recording), as: :json
    end
    assert_response :ok

    @recording.reload
    assert @recording.uploaded?, "status reset so the job's guards pass"
    assert_nil @recording.failed_stage
    assert_nil @recording.error_message
    assert @recording.credit_hold.present?
  end

  test "retry returns 402 when the balance is insufficient" do
    assert_no_enqueued_jobs do
      post retry_recording_path(@recording), as: :json
    end
    assert_response :payment_required
    assert @recording.reload.failed?, "left failed so it can be retried after topping up"
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

  test "a user cannot delete another user's recording" do
    other = users(:two).recordings.create!(status: :complete)
    delete recording_path(other), as: :json
    assert_response :not_found
    assert Recording.exists?(other.id)
  end
end
