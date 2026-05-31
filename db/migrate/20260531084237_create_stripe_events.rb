class CreateStripeEvents < ActiveRecord::Migration[8.1]
  def change
    # PK is the Stripe event id (string) for webhook idempotency (SPEC §6, §12.4).
    create_table :stripe_events, id: false do |t|
      t.string :id, null: false, primary_key: true
      t.string :type, null: false
      t.jsonb :payload, null: false, default: {}
      t.datetime :processed_at

      t.timestamps
    end
  end
end
