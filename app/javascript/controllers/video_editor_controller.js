import { Controller } from "@hotwired/stimulus"

// In-browser, non-destructive trim editor (SPEC §7).
//
// Built to stay responsive on recordings of any length — up to several hours.
// The trick: the browser never decodes or holds the whole file. The <video>
// element streams the source over HTTP range requests (so seeking a 2h video
// fetches only the bytes around the playhead), and editing is purely a matter
// of manipulating an *edit decision list* — an array of [start, end] keep
// segments in seconds. The actual cut happens server-side with ffmpeg when the
// user applies; we only ever POST a few numbers.
//
// Interactions:
//   • click the timeline to seek
//   • drag a segment's edge handles to trim its in/out points
//   • "Split at playhead" cuts the segment under the playhead in two (removing
//     the bit you don't want is then a matter of deleting one half)
//   • delete a segment, or reset back to the full recording
export default class extends Controller {
  static targets = [
    "video", "track", "playhead", "segments", "list",
    "totalKept", "apply", "status"
  ]
  static values = {
    duration: Number,
    applyUrl: String,
    sourceUrl: String,
    refreshUrl: String
  }

  connect() {
    // One keep-segment spanning the whole recording to start.
    this.duration = this.durationValue > 0 ? this.durationValue : 0
    this.segments = [[0, this.duration]]
    this.dragging = null

    this._onTimeUpdate = () => this.renderPlayhead()
    this._onLoaded = () => this.onMetadata()
    this.videoTarget.addEventListener("timeupdate", this._onTimeUpdate)
    this.videoTarget.addEventListener("loadedmetadata", this._onLoaded)
    this.videoTarget.addEventListener("error", () => this.refreshSource())

    this._onPointerMove = (e) => this.onPointerMove(e)
    this._onPointerUp = () => this.endDrag()
    window.addEventListener("pointermove", this._onPointerMove)
    window.addEventListener("pointerup", this._onPointerUp)

    this.render()
  }

  disconnect() {
    this.videoTarget.removeEventListener("timeupdate", this._onTimeUpdate)
    this.videoTarget.removeEventListener("loadedmetadata", this._onLoaded)
    window.removeEventListener("pointermove", this._onPointerMove)
    window.removeEventListener("pointerup", this._onPointerUp)
  }

  // Prefer the real (possibly longer) duration the browser reports once metadata
  // loads — the probed value can be slightly off for streamed WebM.
  onMetadata() {
    const d = this.videoTarget.duration
    if (Number.isFinite(d) && d > 0) {
      const wasFull = this.segments.length === 1 &&
        this.segments[0][0] === 0 && Math.abs(this.segments[0][1] - this.duration) < 0.05
      this.duration = d
      if (wasFull) this.segments = [[0, d]]
      this.render()
    }
  }

  // --- seeking ------------------------------------------------------------
  seek(event) {
    if (this.dragging) return
    this.videoTarget.currentTime = this.timeFromClientX(event.clientX)
  }

  renderPlayhead() {
    if (!this.duration) return
    const pct = (this.videoTarget.currentTime / this.duration) * 100
    this.playheadTarget.style.left = `${this.clampPct(pct)}%`
  }

  // --- segment editing ----------------------------------------------------
  splitAtPlayhead() {
    const t = this.videoTarget.currentTime
    const i = this.segments.findIndex(([s, e]) => t > s && t < e)
    if (i === -1) return
    const [s, e] = this.segments[i]
    // Leave a small gap so the two halves are visibly separate keep-segments.
    const gap = Math.min(0.05, (e - s) / 4)
    this.segments.splice(i, 1, [s, Math.max(s, t - gap)], [Math.min(e, t + gap), e])
    this.render()
  }

  removeSegment(event) {
    const i = Number(event.params.index)
    if (this.segments.length <= 1) {
      this.setStatus("Keep at least one segment, or reset to use the full recording.")
      return
    }
    this.segments.splice(i, 1)
    this.render()
  }

  reset() {
    this.segments = [[0, this.duration]]
    this.render()
  }

  playSegment(event) {
    const [s] = this.segments[Number(event.params.index)]
    this.videoTarget.currentTime = s
    this.videoTarget.play()
  }

  // --- drag handles -------------------------------------------------------
  startDrag(event) {
    event.preventDefault()
    this.dragging = { index: Number(event.params.index), edge: event.params.edge }
  }

  onPointerMove(event) {
    if (!this.dragging) return
    const { index, edge } = this.dragging
    const seg = this.segments[index]
    if (!seg) return
    const t = this.timeFromClientX(event.clientX)
    const minGap = 0.1
    if (edge === "start") {
      seg[0] = Math.min(Math.max(0, t), seg[1] - minGap)
    } else {
      seg[1] = Math.max(Math.min(this.duration, t), seg[0] + minGap)
    }
    this.videoTarget.currentTime = edge === "start" ? seg[0] : seg[1]
    this.render()
  }

  endDrag() {
    this.dragging = null
  }

  // --- apply --------------------------------------------------------------
  async apply() {
    this.applyTarget.disabled = true
    this.setStatus("Applying edits…")
    try {
      const res = await fetch(this.applyUrlValue, {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": this.csrfToken(), Accept: "application/json" },
        body: JSON.stringify({ segments: this.payloadSegments() })
      })
      if (!res.ok) {
        const data = await res.json().catch(() => ({}))
        throw new Error(data.error || res.statusText)
      }
      window.location.href = this.refreshUrlValue
    } catch (err) {
      this.applyTarget.disabled = false
      this.setStatus(`Could not apply edits: ${err.message}`)
    }
  }

  useFullRecording() {
    this.reset()
    this.apply()
  }

  payloadSegments() {
    return this.segments
      .filter(([s, e]) => e - s >= 0.1)
      .map(([s, e]) => ({ start: Number(s.toFixed(3)), end: Number(e.toFixed(3)) }))
  }

  // --- rendering ----------------------------------------------------------
  render() {
    this.renderBlocks()
    this.renderList()
    this.renderPlayhead()
    const kept = this.segments.reduce((sum, [s, e]) => sum + (e - s), 0)
    this.totalKeptTarget.textContent = this.formatTime(kept)
  }

  renderBlocks() {
    this.segmentsTarget.innerHTML = ""
    this.segments.forEach(([s, e], i) => {
      const block = document.createElement("div")
      block.className = "edit-segment"
      block.style.left = `${this.clampPct((s / this.duration) * 100)}%`
      block.style.width = `${this.clampPct(((e - s) / this.duration) * 100)}%`
      block.appendChild(this.handle(i, "start"))
      block.appendChild(this.handle(i, "end"))
      this.segmentsTarget.appendChild(block)
    })
  }

  handle(index, edge) {
    const h = document.createElement("div")
    h.className = `edit-handle edit-handle--${edge}`
    h.dataset.action = "pointerdown->video-editor#startDrag"
    h.dataset.videoEditorIndexParam = index
    h.dataset.videoEditorEdgeParam = edge
    return h
  }

  renderList() {
    this.listTarget.innerHTML = ""
    this.segments.forEach(([s, e], i) => {
      const li = document.createElement("li")
      const label = document.createElement("span")
      label.textContent = `${this.formatTime(s)} – ${this.formatTime(e)}`

      const play = this.button("▶", "video-editor#playSegment", i)
      const del = this.button("Remove", "video-editor#removeSegment", i)
      del.classList.add("linkbtn", "danger")

      li.append(label, play, del)
      this.listTarget.appendChild(li)
    })
  }

  button(text, action, index) {
    const b = document.createElement("button")
    b.type = "button"
    b.textContent = text
    b.dataset.action = `click->${action}`
    b.dataset.videoEditorIndexParam = index
    return b
  }

  // --- helpers ------------------------------------------------------------
  async refreshSource() {
    if (!this.refreshSourceUrl) return
    try {
      const res = await fetch(this.refreshSourceUrl, { headers: { Accept: "application/json" } })
      const data = await res.json()
      if (data.url) this.videoTarget.src = data.url
    } catch (_e) { /* leave the existing source */ }
  }

  get refreshSourceUrl() {
    return this.hasSourceUrlValue ? this.sourceUrlValue : null
  }

  timeFromClientX(clientX) {
    const rect = this.trackTarget.getBoundingClientRect()
    const ratio = (clientX - rect.left) / rect.width
    return Math.min(Math.max(0, ratio), 1) * this.duration
  }

  clampPct(pct) {
    return Math.min(Math.max(0, pct), 100)
  }

  formatTime(seconds) {
    const total = Math.max(0, Math.round(seconds))
    const h = Math.floor(total / 3600)
    const m = Math.floor((total % 3600) / 60)
    const s = total % 60
    const mm = String(m).padStart(2, "0")
    const ss = String(s).padStart(2, "0")
    return h > 0 ? `${h}:${mm}:${ss}` : `${mm}:${ss}`
  }

  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content
  }

  setStatus(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text
  }
}
