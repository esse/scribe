class User < ApplicationRecord
  has_many :recordings, dependent: :destroy

  # Local-first: there are no accounts. A single implicit user owns everything on
  # this machine, auto-provisioned the first time it's needed.
  def self.local
    first || create!(name: "Local user")
  end
end
