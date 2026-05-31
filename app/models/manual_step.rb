class ManualStep < ApplicationRecord
  belongs_to :manual
  belongs_to :frame, optional: true

  validates :position, presence: true

  before_validation :assign_position, on: :create

  private

  def assign_position
    self.position ||= (manual&.steps&.maximum(:position) || 0) + 1
  end
end
