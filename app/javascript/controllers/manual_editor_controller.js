import { Controller } from "@hotwired/stimulus"

// Persists review edits to the manual and its steps (SPEC §10).
export default class extends Controller {
  static targets = ["title", "summary", "status"]
  static values = { url: String }

  async saveManual() {
    await this.patch(this.urlValue, {
      manual: { title: this.titleTarget.value, summary: this.summaryTarget.value }
    })
    this.flash("Saved.")
  }

  async saveStep(event) {
    const id = event.params.id || event.target.dataset.stepId
    const li = event.target.closest("[data-step-id]")
    const step = {
      title: li.querySelector('[data-step-field="title"]').value,
      body_markdown: li.querySelector('[data-step-field="body_markdown"]').value
    }
    await this.patch(`${this.urlValue}/steps/${id}`, { step })
    this.flash("Step saved.")
  }

  async patch(url, body) {
    const res = await fetch(url, {
      method: "PATCH",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": this.csrf() },
      body: JSON.stringify(body)
    })
    if (!res.ok) this.flash("Save failed.")
    return res.json().catch(() => ({}))
  }

  csrf() {
    return document.querySelector('meta[name="csrf-token"]')?.content
  }

  flash(text) {
    if (this.hasStatusTarget) {
      this.statusTarget.textContent = text
      setTimeout(() => { this.statusTarget.textContent = "" }, 2000)
    }
  }
}
