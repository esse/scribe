# Idempotent Stripe webhook processing (SPEC §12.4). Grants credits only here,
# never on the success redirect. Two layers of idempotency:
#   1. stripe_events PK = event id → an event is handled at most once.
#   2. credit_transactions.stripe_session_id unique → a session can't double-grant.
module StripeWebhook
  module_function

  # `event` is a Hash (already-parsed Stripe event). Returns the StripeEvent row.
  def process(event)
    id = event["id"] || event[:id]
    record = StripeEvent.find_or_initialize_by(id:)
    return record if record.processed?

    record.assign_attributes(type: event["type"], payload: event)
    record.save!

    handle(event)
    record.update!(processed_at: Time.current)
    record
  end

  def handle(event)
    case event["type"]
    when "checkout.session.completed"
      grant_for_session(event.dig("data", "object") || {})
    when "charge.refunded"
      refund_for_charge(event.dig("data", "object") || {})
    end
  end

  def grant_for_session(session)
    return unless session["payment_status"] == "paid"

    metadata = session["metadata"] || {}
    user = User.find_by(id: metadata["user_id"])
    return unless user

    Credits::Ledger.grant_purchase!(
      user:,
      credits: metadata["credits"].to_i,
      stripe_session_id: session["id"]
    )
  end

  # Optional v1: reverse credits on refund (SPEC §12.4).
  def refund_for_charge(charge)
    metadata = charge["metadata"] || {}
    user = User.find_by(id: metadata["user_id"])
    return unless user

    Credits::Ledger.refund!(user:, amount: metadata["credits"].to_i, reference: nil)
  end
end
