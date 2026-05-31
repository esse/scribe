module Webhooks
  # Stripe webhook endpoint (SPEC §12.4, §13). Signature-verified and idempotent.
  class StripeController < ApplicationController
    allow_unauthenticated_access
    skip_forgery_protection
    skip_before_action :verify_authenticity_token, raise: false

    # POST /webhooks/stripe
    def create
      payload = request.body.read
      event = verified_event(payload, request.env["HTTP_STRIPE_SIGNATURE"])
      return head(:bad_request) if event.nil?

      StripeWebhook.process(event)
      head :ok
    rescue StandardError => e
      Sentry.capture_exception(e) if defined?(Sentry) && Sentry.initialized?
      head :internal_server_error
    end

    private

    # Verify the signature when a webhook secret is configured; otherwise (dev with
    # Stripe CLI not wired) fall back to parsing the JSON body.
    def verified_event(payload, signature)
      secret = Scribe.config.stripe_webhook_secret
      if secret.present?
        require "stripe"
        begin
          Stripe::Webhook.construct_event(payload, signature.to_s, secret).to_hash.deep_stringify_keys
        rescue Stripe::SignatureVerificationError, JSON::ParserError
          nil
        end
      else
        JSON.parse(payload)
      end
    rescue JSON::ParserError
      nil
    end
  end
end
