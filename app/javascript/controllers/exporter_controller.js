import { Controller } from "@hotwired/stimulus"

// Data-driven export buttons from the format registry (SPEC §11.1, §11.3):
// fetch available formats, trigger an export, poll for the artifact, surface the
// signed download link.
export default class extends Controller {
  static targets = ["buttons", "status"]
  static values = { formatsUrl: String, createUrl: String }

  async connect() {
    const res = await fetch(this.formatsUrlValue, { headers: { Accept: "application/json" } })
    const { formats } = await res.json()
    this.buttonsTarget.innerHTML = ""
    formats.forEach((format) => {
      const btn = document.createElement("button")
      btn.textContent = format.toUpperCase()
      btn.addEventListener("click", () => this.export(format))
      this.buttonsTarget.appendChild(btn)
    })
  }

  async export(format) {
    this.status(`Exporting ${format}…`)
    const res = await fetch(this.createUrlValue, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": this.csrf() },
      body: JSON.stringify({ format })
    })
    const { export_id } = await res.json()
    this.pollExport(export_id)
  }

  async pollExport(id) {
    const tick = async () => {
      const res = await fetch(`/exports/${id}`, { headers: { Accept: "application/json" } })
      const data = await res.json()
      if (data.status === "ready") {
        this.status("")
        window.location.href = data.download_url
      } else if (data.status === "failed") {
        this.status(`Export failed: ${data.error_message || ""}`)
      } else {
        setTimeout(tick, 1500)
      }
    }
    tick()
  }

  csrf() {
    return document.querySelector('meta[name="csrf-token"]')?.content
  }

  status(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text
  }
}
