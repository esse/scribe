class AddTokenUsageToManuals < ActiveRecord::Migration[8.1]
  def change
    # Per-generation token usage for cost logging / future token-based metering
    # (SPEC §9.4, §13.4).
    add_column :manuals, :input_tokens, :integer
    add_column :manuals, :output_tokens, :integer
  end
end
