class RecordingsController < ApplicationController
  before_action :set_recording, only: %i[show complete]

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

  private

  def set_recording
    @recording = Current.user.recordings.find(params[:id])
  end
end
