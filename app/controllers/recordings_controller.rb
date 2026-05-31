class RecordingsController < ApplicationController
  before_action :set_recording, only: %i[show complete edit apply_edits source_url retry destroy]

  # Which job re-runs each failed stage (SPEC §8.1, §16.7).
  RETRY_JOBS = {
    "editing" => ApplyEditsJob,
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

  # POST /recordings/:id/complete — finalize upload and reserve credits
  # (SPEC §7.2 step 4, §13.3). Returns 402 if the balance is insufficient.
  #
  # The pipeline no longer starts here: the user is handed to the in-browser
  # editor to (optionally) trim the recording, and processing kicks off from
  # #apply_edits. Credits are held now, on the full uploaded duration, as the
  # gate; trimming only shortens the video, so the hold stays sufficient.
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
    render json: {
      id: @recording.id,
      status: @recording.status,
      estimated_credits: estimate,
      edit_url: edit_recording_path(@recording)
    }
  end

  # GET /recordings/:id/edit — in-browser trim editor (SPEC §7). Plays the source
  # over signed, range-served URLs so videos of any length stay responsive.
  def edit
    redirect_to recording_path(@recording), alert: "This recording can no longer be edited." unless @recording.editable?
  end

  # GET /recordings/:id/source_url — a fresh signed URL for the source video, so
  # the editor can refresh playback if a short-lived token expires mid-session.
  def source_url
    head(:not_found) and return unless @recording.storage_key.present? && @recording.raw_video_purged_at.nil?

    render json: { url: Storage.signed_url(@recording.storage_key), mime: @recording.mime.presence || "video/webm" }
  end

  # POST /recordings/:id/apply_edits — persist the editor's keep-segments and
  # start processing. An empty / full-length list means "use the whole recording".
  def apply_edits
    unless @recording.editable?
      render json: { error: "not_editable" }, status: :unprocessable_entity
      return
    end

    segments = Media::Editor.normalize_segments(edit_params, duration_seconds: @recording.duration_seconds)
    @recording.update!(edit_segments: segments, status: :editing)
    ApplyEditsJob.perform_later(@recording.id)

    respond_to do |format|
      format.html { redirect_to recording_path(@recording), notice: "Applying edits…" }
      format.json { render json: { id: @recording.id, status: @recording.status, segments: segments } }
    end
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

  # Keep-segments arrive as an array of {start,end} objects (seconds). Permit the
  # array wholesale; Media::Editor validates/clamps the actual values.
  def edit_params
    params.permit(segments: %i[start end]).fetch(:segments, [])
  end

  def set_recording
    @recording = Current.user.recordings.find(params[:id])
  end
end
