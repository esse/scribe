class Manual < ApplicationRecord
  belongs_to :recording
  has_one :user, through: :recording
  has_many :steps, -> { order(:position) }, class_name: "ManualStep", dependent: :destroy
  has_many :exports, dependent: :destroy

  enum :status, { generating: 0, ready: 1, failed: 2 }

  validates :title, presence: true, if: :ready?
end
