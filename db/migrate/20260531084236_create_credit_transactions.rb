class CreateCreditTransactions < ActiveRecord::Migration[8.1]
  def change
    create_table :credit_transactions do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :kind, null: false
      t.integer :amount, null: false # signed integer credits (SPEC §6, §12)
      t.integer :state, null: false, default: 0
      # Polymorphic-ish reference to the thing this entry relates to (e.g. a Recording hold).
      t.string :reference_type
      t.bigint :reference_id
      t.string :stripe_session_id

      t.timestamps
    end

    add_index :credit_transactions, %i[user_id state]
    add_index :credit_transactions, %i[reference_type reference_id]
    # Guarantees a Stripe purchase can be granted at most once (SPEC §12.4 idempotency).
    add_index :credit_transactions, :stripe_session_id, unique: true, where: "stripe_session_id IS NOT NULL"
  end
end
