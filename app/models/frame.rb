class Frame < ApplicationRecord
  belongs_to :recording
  has_many :manual_steps, dependent: :nullify

  # How the frame entered the system (SPEC §6, §8.5).
  enum :source, { scene: 0, on_demand: 1 }

  validates :timestamp_ms, presence: true,
                           uniqueness: { scope: :recording_id }

  # Nearest extracted frame to a requested timestamp, used when snapping
  # Claude's chosen `frame_timestamp_ms` to a real row (SPEC §8.5).
  def self.nearest_to(recording, timestamp_ms)
    recording.frames
             .select("frames.*, ABS(timestamp_ms - #{timestamp_ms.to_i}) AS distance")
             .order("distance ASC")
             .first
  end
end
