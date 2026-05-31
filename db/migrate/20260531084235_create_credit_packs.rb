class CreateCreditPacks < ActiveRecord::Migration[8.1]
  def change
    create_table :credit_packs do |t|
      t.string :name, null: false
      t.integer :credits, null: false
      t.string :stripe_price_id, null: false
      t.integer :price_cents, null: false
      t.string :currency, null: false, default: "usd"
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :credit_packs, :stripe_price_id, unique: true
  end
end
