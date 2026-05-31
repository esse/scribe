require "test_helper"

# Upload completion, credit reservation and 402 gating (SPEC §7.2, §13.3), plus
# per-user authorization (SPEC §13, §14).
class RecordingsFlowTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
    sign_in_as(@user)
    @recording = @user.recordings.create!(status: :recording)
    @tus_id = "/files/abc123"
    stage_tus_upload(@tus_id)
  end

  test "complete reserves credits and hands off to the editor (pipeline starts on apply)" do
    Credits::Ledger.grant_purchase!(user: @user, credits: 50, stripe_session_id: "cs_funded")

    # The pipeline no longer starts at /complete — the editor kicks it off on apply.
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
    assert @recording.credit_hold.present?
    assert_operator @user.available_credits, :<, 50, "a hold was placed"
  end

  test "complete returns 402 and does not enqueue when balance is insufficient" do
    assert_no_enqueued_jobs do
      post complete_recording_path(@recording), params: { tus_upload_id: @tus_id }
    end
    assert_response :payment_required
    body = JSON.parse(response.body)
    assert_equal "insufficient_credits", body["error"]
    assert @recording.reload.recording?, "status unchanged when gated"
  end

  test "a user cannot complete another user's recording" do
    other = users(:two).recordings.create!(status: :recording)
    post complete_recording_path(other), params: { tus_upload_id: @tus_id }
    assert_response :not_found, "scoped lookup hides other users' recordings"
    assert other.reload.recording?
  end

  test "unauthenticated users are redirected to sign in" do
    sign_out
    post complete_recording_path(@recording), params: { tus_upload_id: @tus_id }
    assert_redirected_to new_session_path
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
