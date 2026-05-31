class ManualsController < ApplicationController
  before_action :set_manual

  # GET /manuals/:id — manual + ordered steps + signed frame URLs (SPEC §13).
  def show
    respond_to do |format|
      format.html
      format.json { render json: manual_json(@manual) }
    end
  end

  # PATCH /manuals/:id — edit title/summary (SPEC §10, §13).
  def update
    if @manual.update(manual_params)
      render json: manual_json(@manual)
    else
      render json: { errors: @manual.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def set_manual
    @manual = Manual.joins(recording: :user)
                    .where(users: { id: Current.user.id })
                    .find(params[:id])
  end

  def manual_params
    params.require(:manual).permit(:title, :summary)
  end

  def manual_json(manual)
    {
      id: manual.id,
      title: manual.title,
      summary: manual.summary,
      status: manual.status,
      steps: manual.steps.map { |s| step_json(s) }
    }
  end

  def step_json(step)
    {
      id: step.id,
      position: step.position,
      title: step.title,
      body_markdown: step.body_markdown,
      source_start_ms: step.source_start_ms,
      source_end_ms: step.source_end_ms,
      frame_id: step.frame_id,
      frame_url: step.frame && Storage.signed_url(step.frame.storage_key)
    }
  end
end
