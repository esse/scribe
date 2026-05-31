require "test_helper"

# Webhook idempotency (SPEC §12.4, §15): replaying the same event grants credits
# exactly once. Runs without a webhook secret so the controller parses the JSON
# body directly (signature verification is exercised when STRIPE_WEBHOOK_SECRET
# is set in real environments).
class StripeWebhookTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @event = {
      "id" => "evt_test_123",
      "type" => "checkout.session.completed",
      "data" => {
        "object" => {
          "id" => "cs_session_abc",
          "payment_status" => "paid",
          "metadata" => { "user_id" => @user.id.to_s, "credit_pack_id" => "1", "credits" => "300" }
        }
      }
    }
  end

  test "replaying the same event grants credits only once" do
    3.times do
      post webhooks_stripe_path, params: @event.to_json, headers: { "CONTENT_TYPE" => "application/json" }
      assert_response :ok
    end

    assert_equal 1, StripeEvent.where(id: "evt_test_123").count
    assert_equal 1, @user.credit_transactions.where(stripe_session_id: "cs_session_abc").count
    assert_equal 300, @user.available_credits
  end

  test "unpaid sessions do not grant credits" do
    @event["data"]["object"]["payment_status"] = "unpaid"
    post webhooks_stripe_path, params: @event.to_json, headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :ok
    assert_equal 0, @user.available_credits
  end

  test "two different events for the same session still grant once" do
    post webhooks_stripe_path, params: @event.to_json, headers: { "CONTENT_TYPE" => "application/json" }
    @event["id"] = "evt_test_456" # a redelivery under a new event id
    post webhooks_stripe_path, params: @event.to_json, headers: { "CONTENT_TYPE" => "application/json" }

    assert_equal 1, @user.credit_transactions.where(stripe_session_id: "cs_session_abc").count,
                 "unique stripe_session_id prevents a second grant even across event ids"
    assert_equal 300, @user.available_credits
  end
end
