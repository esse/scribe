class CreditPack < ApplicationRecord
  has_many :credit_transactions, foreign_key: :reference_id,
                                 primary_key: :id,
                                 inverse_of: false,
                                 dependent: :nullify

  validates :name, :credits, :stripe_price_id, :price_cents, presence: true
  validates :credits, numericality: { greater_than: 0 }

  scope :active, -> { where(active: true) }

  def price
    format("%.2f %s", price_cents / 100.0, currency.upcase)
  end
end
