class Recording < ApplicationRecord
  belongs_to :user
  has_one :transcript, dependent: :destroy
  has_many :frames, dependent: :destroy
  has_one :manual, dependent: :destroy

  # Linear pipeline state machine (SPEC §8.1).
  #   recording → uploaded → editing → transcribing → extracting_frames → generating_manual → complete
  #   any stage may transition to → failed (with failed_stage)
  # `editing` is the optional in-browser-trim apply stage; it sits between upload
  # and transcription. New value appended (7) so existing rows keep their codes.
  enum :status, {
    recording: 0,
    uploaded: 1,
    transcribing: 2,
    extracting_frames: 3,
    generating_manual: 4,
    complete: 5,
    failed: 6,
    editing: 7
  }

  # Stage names recorded in `failed_stage` so the retry UI knows where to resume (SPEC §8.1).
  enum :failed_stage, {
    upload: 0,
    transcription: 1,
    frame_extraction: 2,
    manual_generation: 3,
    editing: 4
  }, prefix: :failed_at

  validates :scene_threshold, numericality: { greater_than: 0, less_than_or_equal_to: 1 }

  # The video the pipeline should actually process: the trimmed output once the
  # editor has applied edits, otherwise the originally uploaded source.
  def processing_storage_key
    edited_storage_key.presence || storage_key
  end

  # The recording is editable while it still has a usable source video and the
  # pipeline hasn't moved past the editing stage (or has failed, so it can be
  # re-trimmed and retried).
  def editable?
    storage_key.present? && raw_video_purged_at.nil? &&
      (uploaded? || editing? || (failed? && failed_at_editing?))
  end

  # Mark the pipeline as failed at a given stage and persist the error (SPEC §8.1).
  def fail!(stage:, error:)
    update!(status: :failed, failed_stage: stage, error_message: error.to_s.truncate(1000))
  end
end
