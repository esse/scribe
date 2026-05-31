class CreditsController < ApplicationController
  # GET /credits — billing page (SPEC §12).
  def index
    @balance = Current.user.available_credits
    @packs = CreditPack.active.order(:credits)
  end

  # GET /credits/balance
  def balance
    render json: { balance: Current.user.available_credits }
  end

  # GET /credits/packs
  def packs
    render json: { packs: CreditPack.active.order(:credits).map { |p| pack_json(p) } }
  end

  # POST /credits/checkout { pack_id } — start a Stripe Checkout Session (SPEC §12.4).
  # Credits are granted only via webhook, never the success redirect.
  def checkout
    pack = CreditPack.active.find(params.require(:pack_id))
    session = StripeCheckout.create_session(user: Current.user, pack:)
    render json: { checkout_url: session.url }
  rescue StripeCheckout::NotConfigured => e
    render json: { error: e.message }, status: :service_unavailable
  end

  private

  def pack_json(pack)
    { id: pack.id, name: pack.name, credits: pack.credits, price_cents: pack.price_cents, currency: pack.currency }
  end
end
