# Idempotent seeds (SPEC §12.2). Credit-pack sizes/prices are placeholders.
# TODO(decision): confirm pack sizes/prices and map to real Stripe Price ids.
[
  { name: "Starter", credits: 60,   price_cents: 900,   stripe_price_id: "price_starter" },
  { name: "Pro",     credits: 300,  price_cents: 3900,  stripe_price_id: "price_pro" },
  { name: "Studio",  credits: 1000, price_cents: 9900,  stripe_price_id: "price_studio" }
].each do |attrs|
  pack = CreditPack.find_or_initialize_by(stripe_price_id: attrs[:stripe_price_id])
  pack.update!(attrs.merge(currency: "usd", active: true))
end

puts "Seeded #{CreditPack.active.count} credit packs."
