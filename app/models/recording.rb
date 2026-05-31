class Recording < ApplicationRecord
  belongs_to :user
  has_one :transcript, dependent: :destroy
  has_many :frames, dependent: :destroy
  has_one :manual, dependent: :destroy

  # Linear pipeline state machine (SPEC §8.1).
  #   recording → uploaded → transcribing → extracting_frames → generating_manual → complete
  #   any stage may transition to → failed (with failed_stage)
  enum :status, {
    recording: 0,
    uploaded: 1,
    transcribing: 2,
    extracting_frames: 3,
    generating_manual: 4,
    complete: 5,
    failed: 6
  }

  # Stage names recorded in `failed_stage` so the retry UI knows where to resume (SPEC §8.1).
  enum :failed_stage, {
    upload: 0,
    transcription: 1,
    frame_extraction: 2,
    manual_generation: 3
  }, prefix: :failed_at

  validates :scene_threshold, numericality: { greater_than: 0, less_than_or_equal_to: 1 }

  # The credit hold placed for this recording at /complete (SPEC §13.3).
  def credit_hold
    CreditTransaction.where(reference: self, kind: :hold).order(:created_at).last
  end

  # Mark the pipeline as failed at a given stage and persist the error (SPEC §8.1).
  def fail!(stage:, error:)
    update!(status: :failed, failed_stage: stage, error_message: error.to_s.truncate(1000))
  end
end
