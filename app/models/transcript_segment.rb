class TranscriptSegment < ApplicationRecord
  belongs_to :transcript

  validates :position, :start_ms, :end_ms, presence: true
end
