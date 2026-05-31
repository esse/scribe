class StripeEvent < ApplicationRecord
  self.primary_key = "id"
  # `type` holds the Stripe event type, not an STI subclass.
  self.inheritance_column = nil

  validates :type, presence: true

  def processed?
    processed_at.present?
  end
end
