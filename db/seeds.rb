# Local-first: no accounts, no billing, nothing to seed. The single local user
# is created on demand. Kept so `bin/rails db:seed` stays a harmless no-op.
User.local

puts "Scribe is local-first — nothing to seed."
