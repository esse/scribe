import { Controller } from "@hotwired/stimulus"

// Polls a recording's pipeline status and reveals the manual link on completion
// (SPEC §8.1, §13).
export default class extends Controller {
  static targets = ["badge", "link", "manualLink"]
  static values = { url: String }

  connect() {
    this.poll()
    this.timer = setInterval(() => this.poll(), 2500)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  async poll() {
    try {
      const res = await fetch(this.urlValue, { headers: { Accept: "application/json" } })
      const data = await res.json()
      if (this.hasBadgeTarget) this.badgeTarget.textContent = this.humanize(data.status)
      this.mark(data.status)

      if (data.status === "complete" && data.manual_id) {
        this.manualLinkTarget.href = `/manuals/${data.manual_id}`
        this.linkTarget.hidden = false
        clearInterval(this.timer)
      } else if (data.status === "failed") {
        clearInterval(this.timer)
        window.location.reload()
      }
    } catch (_e) { /* transient; keep polling */ }
  }

  mark(status) {
    const order = ["uploaded", "editing", "transcribing", "extracting_frames", "generating_manual", "complete"]
    const idx = order.indexOf(status)
    this.element.querySelectorAll("[data-stage]").forEach((li) => {
      li.classList.toggle("done", order.indexOf(li.dataset.stage) <= idx && idx >= 0)
    })
  }

  humanize(s) {
    return (s || "").replace(/_/g, " ").replace(/^\w/, (c) => c.toUpperCase())
  }
}
