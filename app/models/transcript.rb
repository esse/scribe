class Transcript < ApplicationRecord
  belongs_to :recording
  has_many :segments, -> { order(:position) }, class_name: "TranscriptSegment", dependent: :destroy

  enum :status, { pending: 0, ready: 1, failed: 2 }

  # Timestamped transcript rendered for the Claude prompt (SPEC §9.3).
  def to_prompt_text
    segments.map do |s|
      "[#{format_ts(s.start_ms)}–#{format_ts(s.end_ms)}] #{s.text}"
    end.join("\n")
  end

  private

  def format_ts(ms)
    total = ms / 1000
    format("%02d:%02d", total / 60, total % 60)
  end
end
