class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    # Local-first: there are no accounts. A single implicit local user owns all
    # recordings (auto-provisioned on first use). The optional name is purely
    # cosmetic (e.g. an author line on exported manuals).
    create_table :users do |t|
      t.string :name

      t.timestamps
    end
  end
end
