module Manuals
  # Edit / reorder / swap-frame for a step (SPEC §10, §13).
  class StepsController < ApplicationController
    before_action :set_step

    # PATCH /manuals/:manual_id/steps/:id
    def update
      attrs = step_params.to_h

      # Swap frame: accept another extracted frame, or request an on-demand frame
      # at a scrubbed timestamp (SPEC §10).
      if attrs.key?(:frame_timestamp_ms)
        frame = resolve_frame(attrs.delete(:frame_timestamp_ms))
        attrs[:frame_id] = frame&.id
      end

      if @step.update(attrs)
        render json: step_json(@step)
      else
        render json: { errors: @step.errors.full_messages }, status: :unprocessable_entity
      end
    end

    private

    def set_step
      @step = ManualStep.joins(manual: { recording: :user })
                        .where(users: { id: Current.user.id }, manuals: { id: params[:manual_id] })
                        .find(params[:id])
    end

    def step_params
      params.require(:step).permit(:title, :body_markdown, :position, :frame_id, :frame_timestamp_ms)
    end

    def resolve_frame(timestamp_ms)
      recording = @step.manual.recording
      recording.frames.find_by(timestamp_ms:) ||
        Frame.nearest_to(recording, timestamp_ms.to_i)
      # NOTE: on-demand extraction for a brand-new scrub time is enqueued via a
      # dedicated job in production; here we snap to the nearest existing frame.
      # TODO(decision): synchronous on-demand extraction vs background for editor swaps.
    end

    def step_json(step)
      {
        id: step.id, position: step.position, title: step.title,
        body_markdown: step.body_markdown, frame_id: step.frame_id,
        frame_url: step.frame && Storage.signed_url(step.frame.storage_key)
      }
    end
  end
end
