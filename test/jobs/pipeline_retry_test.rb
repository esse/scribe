require "test_helper"

# Per-stage retry + failure classification (SPEC §8.1, §16.7).
class PipelineRetryTest < ActiveSupport::TestCase
  # Minimal job that exposes the PipelineStage helpers for direct testing.
  class ProbeJob < ApplicationJob
    include PipelineStage
    def call_stage(recording, stage:, &) = run_stage(recording, stage:, &)
    def exhaust(error) = record_exhausted_failure(error)
  end

  setup do
    @user = User.local
    @recording = @user.recordings.create!(status: :transcribing, storage_key: "x")
  end

  test "transient errors are wrapped so they retry instead of failing immediately" do
    job = ProbeJob.new
    assert_raises(PipelineStage::TransientError) do
      job.call_stage(@recording, stage: :transcription) { raise Net::ReadTimeout }
    end
    # Not marked failed yet — retry_on will get another attempt.
    assert @recording.reload.transcribing?
  end

  test "permanent errors mark the recording failed" do
    job = ProbeJob.new
    job.call_stage(@recording, stage: :transcription) { raise "bad input" }

    @recording.reload
    assert @recording.failed?
    assert_equal "transcription", @recording.failed_stage
    assert_equal "bad input", @recording.error_message
  end

  test "exhausted transient retries record a permanent failure" do
    error = PipelineStage::TransientError.new(recording_id: @recording.id, stage: :frame_extraction, cause: Net::ReadTimeout.new)
    ProbeJob.new.exhaust(error)

    @recording.reload
    assert @recording.failed?
    assert_equal "frame_extraction", @recording.failed_stage
  end
end
