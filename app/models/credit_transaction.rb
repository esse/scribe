class CreditTransaction < ApplicationRecord
  belongs_to :user
  belongs_to :reference, polymorphic: true, optional: true

  # Append-only ledger entry kinds (SPEC §12.1).
  enum :kind, {
    purchase: 0,    # (+) granted on confirmed Stripe payment
    hold: 1,        # (−) reservation placed when processing starts
    release: 2,     # (+) reverses a hold (unused in flat model; kept for symmetry)
    adjustment: 3,  # (±) manual support correction
    refund: 4       # (−) Stripe refund
  }

  # Lifecycle of an individual entry (SPEC §12.1).
  #   pending  → counts against available balance (active hold / unconfirmed purchase)
  #   settled  → confirmed and final
  #   void     → excluded from balance (a hold that was released on failure)
  enum :state, { pending: 0, settled: 1, void: 2 }

  validates :amount, presence: true
  validates :stripe_session_id, uniqueness: true, allow_nil: true

  # Entries that count toward the available balance (SPEC §12.1):
  #   available_balance(user) = SUM(amount) WHERE state IN ('settled','pending')
  scope :counted, -> { where(state: %i[pending settled]) }
end
