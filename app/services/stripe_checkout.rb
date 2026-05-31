# Stripe Checkout Session creation for one-time credit purchases (SPEC §12.4).
module StripeCheckout
  class NotConfigured < StandardError; end

  module_function

  def create_session(user:, pack:)
    raise NotConfigured, "STRIPE_SECRET_KEY not set" if Scribe.config.stripe_secret_key.blank?

    require "stripe"
    customer_id = ensure_customer(user)

    Stripe::Checkout::Session.create(
      mode: "payment",
      customer: customer_id,
      line_items: [ { price: pack.stripe_price_id, quantity: 1 } ],
      success_url: Scribe.config.stripe_success_url,
      cancel_url: Scribe.config.stripe_cancel_url,
      metadata: { user_id: user.id, credit_pack_id: pack.id, credits: pack.credits }
    )
  end

  # Ensure a Stripe Customer exists for the user and cache its id (SPEC §12.4).
  def ensure_customer(user)
    return user.stripe_customer_id if user.stripe_customer_id.present?

    customer = Stripe::Customer.create(email: user.email_address, metadata: { user_id: user.id })
    user.update!(stripe_customer_id: customer.id)
    customer.id
  end
end
