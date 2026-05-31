import { Controller } from "@hotwired/stimulus"

// Starts a Stripe Checkout Session and redirects (SPEC §12.4). Credits are
// granted via webhook, never on the success redirect.
export default class extends Controller {
  async buy(event) {
    const packId = event.target.dataset.packId
    const res = await fetch("/credits/checkout", {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": this.csrf() },
      body: JSON.stringify({ pack_id: packId })
    })
    if (!res.ok) {
      const data = await res.json().catch(() => ({}))
      alert(data.error || "Checkout is unavailable.")
      return
    }
    const { checkout_url } = await res.json()
    window.location.href = checkout_url
  }

  csrf() {
    return document.querySelector('meta[name="csrf-token"]')?.content
  }
}
