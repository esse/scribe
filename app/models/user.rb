class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :recordings, dependent: :destroy
  has_many :credit_transactions, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  # Available credit balance, derived from the ledger — never stored (SPEC §12.1).
  def available_credits
    credit_transactions.counted.sum(:amount)
  end
end
