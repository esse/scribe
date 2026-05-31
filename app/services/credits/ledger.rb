module Credits
  # The single entry point for all credit mutations (SPEC §5: "All money/credit
  # mutations go through the ledger — never mutate a cached balance directly").
  #
  # The balance is always derived: SUM(amount) WHERE state IN ('settled','pending').
  module Ledger
    module_function

    def balance(user)
      user.credit_transactions.counted.sum(:amount)
    end

    # Grant purchased credits. Idempotent on stripe_session_id so webhook retries
    # can never double-grant (SPEC §12.4).
    def grant_purchase!(user:, credits:, stripe_session_id:)
      if stripe_session_id.present? && (existing = CreditTransaction.find_by(stripe_session_id:))
        return existing
      end

      CreditTransaction.create!(
        user:,
        kind: :purchase,
        amount: credits.to_i,
        state: :settled,
        stripe_session_id:
      )
    rescue ActiveRecord::RecordNotUnique
      # Lost a concurrent race; the winning row is authoritative.
      CreditTransaction.find_by!(stripe_session_id:)
    end

    # Reserve credits for a unit of work. Takes a per-user row lock, checks the
    # balance, and inserts a pending negative `hold` atomically so two concurrent
    # requests can't both spend the last credits (SPEC §13.3).
    #
    # Returns the hold transaction. Raises InsufficientCredits on a short balance.
    def hold!(user:, amount:, reference:)
      amount = amount.to_i
      raise ArgumentError, "hold amount must be positive" unless amount.positive?

      CreditTransaction.transaction do
        # SELECT ... FOR UPDATE on the user row serializes balance checks per user.
        user.lock!
        available = balance(user)
        raise InsufficientCredits.new(required: amount, available:) if available < amount

        CreditTransaction.create!(
          user:,
          kind: :hold,
          amount: -amount,
          state: :pending,
          reference:
        )
      end
    end

    # Settle a hold to its actual cost on pipeline success (SPEC §13.3). Under the
    # flat per-minute model actual == estimate, but `actual_amount` lets token-based
    # metering slot in later without a schema change.
    def settle!(hold, actual_amount: nil)
      return hold unless hold&.hold? && hold.pending?

      actual = actual_amount ? -actual_amount.to_i.abs : hold.amount
      # Never settle higher than the reserved estimate.
      actual = [ actual, hold.amount ].max
      hold.update!(amount: actual, state: :settled)
      hold
    end

    # Void a hold on failure so it stops counting against the balance (SPEC §13.3).
    def void!(hold)
      return hold unless hold&.hold? && hold.pending?

      hold.update!(state: :void)
      hold
    end

    # Support/dispute corrections (SPEC §12.1).
    def adjust!(user:, amount:, reference: nil)
      CreditTransaction.create!(user:, kind: :adjustment, amount: amount.to_i, state: :settled, reference:)
    end

    def refund!(user:, amount:, reference: nil)
      CreditTransaction.create!(user:, kind: :refund, amount: -amount.to_i.abs, state: :settled, reference:)
    end
  end
end
