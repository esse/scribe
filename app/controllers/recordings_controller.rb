class RecordingsController < ApplicationController
  before_action :set_recording, only: %i[show complete retry destroy]

  # Which job re-runs each failed stage (SPEC §8.1, §16.7).
  RETRY_JOBS = {
    "transcription" => TranscribeJob,
    "frame_extraction" => ExtractFramesJob,
    "manual_generation" => GenerateManualJob
  }.freeze

  # Recorder UI (SPEC §7.1).
  def new
    @recording = nil
  end

  def index
    @recordings = Current.user.recordings.order(created_at: :desc)
  end

  # POST /recordings — create the row and hand back the tus endpoint (SPEC §7.2 step 1).
  def create
    recording = Current.user.recordings.create!(status: :recording)
    render json: {
      id: recording.id,
      tus_endpoint: "/files",
      upload_url: nil # client creates the tus upload, then POSTs /complete with its id
    }, status: :created
  end

  # GET /recordings/:id — status + progress (SPEC §13).
  def show
    respond_to do |format|
      format.html
      format.json do
        render json: {
          id: @recording.id,
          status: @recording.status,
          duration_seconds: @recording.duration_seconds,
          failed_stage: @recording.failed_stage,
          error_message: @recording.error_message,
          manual_id: @recording.manual&.id
        }
      end
    end
  end

  # POST /recordings/:id/complete — finalize upload, reserve credits, start pipeline
  # (SPEC §7.2 step 4, §13.3). Returns 402 if the balance is insufficient.
  def complete
    finalized = RecordingUpload.finalize(@recording, params.require(:tus_upload_id))
    @recording.assign_attributes(
      tus_upload_id: params[:tus_upload_id],
      storage_key: finalized[:storage_key],
      duration_seconds: finalized[:duration_seconds],
      mime: finalized[:mime]
    )

    estimate = Credits::Meter.estimate_for(@recording)
    begin
      Credits::Ledger.hold!(user: Current.user, amount: estimate, reference: @recording)
    rescue Credits::InsufficientCredits => e
      render json: { error: "insufficient_credits", required: e.required, available: e.available }, status: :payment_required
      return
    end

    @recording.uploaded!
    TranscribeJob.perform_later(@recording.id)
    render json: { id: @recording.id, status: @recording.status, estimated_credits: estimate }
  end

  # POST /recordings/:id/retry — re-run a failed stage (SPEC §8.1, §16.7). The
  # hold was voided on failure, so we re-reserve credits (402 if short) and
  # re-enqueue the stage's job, which resumes from already-persisted artifacts.
  def retry
    unless @recording.failed?
      respond_with_retry(error: "not_failed", status: :unprocessable_entity)
      return
    end

    job = RETRY_JOBS[@recording.failed_stage] || TranscribeJob
    estimate = Credits::Meter.estimate_for(@recording)
    begin
      Credits::Ledger.hold!(user: Current.user, amount: estimate, reference: @recording)
    rescue Credits::InsufficientCredits => e
      respond_with_retry(error: "insufficient_credits", required: e.required, available: e.available, status: :payment_required)
      return
    end

    @recording.update!(status: :uploaded, error_message: nil, failed_stage: nil)
    job.perform_later(@recording.id)
    respond_with_retry(status: :ok)
  end

  # DELETE /recordings/:id — remove the recording and all of its stored objects:
  # video, frames, transcript, manual, exports (SPEC §14).
  def destroy
    RecordingPurge.destroy!(@recording)
    respond_to do |format|
      format.html { redirect_to recordings_path, notice: "Recording deleted." }
      format.json { head :no_content }
    end
  end

  private

  def respond_with_retry(status:, **payload)
    respond_to do |format|
      format.html do
        if status == :ok
          redirect_to recording_path(@recording), notice: "Retrying…"
        else
          redirect_to recording_path(@recording), alert: payload[:error]&.humanize
        end
      end
      format.json { render json: { id: @recording.id, status: @recording.status }.merge(payload), status: }
    end
  end

  def set_recording
    @recording = Current.user.recordings.find(params[:id])
  end
end
