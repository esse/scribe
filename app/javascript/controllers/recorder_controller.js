import { Controller } from "@hotwired/stimulus"
import * as tus from "tus-js-client"

// Screen + mic recording with continuous resumable upload (SPEC §7.1, §7.2).
//
// Mixes the display video track with the mic audio track so narration stays
// aligned to the screen, feeds each MediaRecorder chunk into a single tus upload
// (ordered, resumable byte-append → one valid WebM in storage), and calls
// /recordings/:id/complete when the user stops sharing.
export default class extends Controller {
  static targets = ["start", "stop", "status", "systemAudio"]

  connect() {
    this.chunks = []
    this.recordingId = null
  }

  async start() {
    if (!navigator.mediaDevices?.getDisplayMedia) {
      this.setStatus("Screen recording is not supported in this browser.")
      return
    }

    try {
      const withSystemAudio = this.hasSystemAudioTarget && this.systemAudioTarget.checked
      const display = await navigator.mediaDevices.getDisplayMedia({
        video: { frameRate: 30 },
        audio: withSystemAudio
      })
      const mic = await navigator.mediaDevices.getUserMedia({ audio: true })
      const mixed = new MediaStream([...display.getVideoTracks(), ...mic.getAudioTracks()])

      // Create the recording row + tus endpoint (SPEC §7.2 step 1).
      const created = await this.postJSON("/recordings", {})
      this.recordingId = created.id

      this.upload = await this.beginUpload(created.tus_endpoint)

      this.recorder = new MediaRecorder(mixed, { mimeType: this.pickMimeType() })
      this.recorder.ondataavailable = (e) => { if (e.data.size) this.appendChunk(e.data) }
      this.recorder.start(5000) // emit a chunk every 5s (SPEC §7.1)

      // User clicks the browser's native "Stop sharing" → stop the recorder too.
      display.getVideoTracks()[0].addEventListener("ended", () => this.stop())

      this.toggle(true)
      this.setStatus("Recording…")
    } catch (err) {
      this.setStatus(`Permission denied or capture failed: ${err.message}`)
    }
  }

  async stop() {
    if (!this.recorder || this.recorder.state === "inactive") return
    this.recorder.stop()
    this.setStatus("Finalizing upload…")

    // Wait for the final chunk + flush, then mark complete.
    await new Promise((resolve) => setTimeout(resolve, 500))
    await this.finishUpload()

    try {
      const result = await this.postJSON(`/recordings/${this.recordingId}/complete`, {
        tus_upload_id: this.upload.url
      })
      this.setStatus(`Uploaded. Processing started (${result.estimated_credits} credits reserved).`)
      window.location.href = `/recordings/${this.recordingId}`
    } catch (err) {
      this.setStatus(`Upload finalize failed: ${err.message}`)
    }
    this.toggle(false)
  }

  // --- tus upload plumbing ------------------------------------------------
  beginUpload(endpoint) {
    // Open a zero-length upload we can append to as chunks arrive.
    return new Promise((resolve, reject) => {
      const upload = new tus.Upload(new Blob([]), {
        endpoint,
        retryDelays: [0, 1000, 3000, 5000],
        chunkSize: 5 * 1024 * 1024,
        metadata: { filename: "recording.webm", filetype: "video/webm" },
        onError: (error) => this.setStatus(`Upload error: ${error}`),
        onSuccess: () => {}
      })
      // Defer the actual start until we have data; resolve the handle now.
      resolve(upload)
    })
  }

  appendChunk(blob) {
    this.chunks.push(blob)
    // Rebuild the in-order blob and (re)start the tus upload so storage always
    // holds the valid concatenation starting with the header chunk.
    const file = new Blob(this.chunks, { type: "video/webm" })
    this.upload.file = file
    if (!this.uploadStarted) {
      this.uploadStarted = true
      this.upload.start()
    }
  }

  finishUpload() {
    return new Promise((resolve) => {
      const file = new Blob(this.chunks, { type: "video/webm" })
      this.upload.options.onSuccess = resolve
      this.upload.file = file
      this.upload.start()
      // Safety net in case onSuccess already fired.
      setTimeout(resolve, 4000)
    })
  }

  pickMimeType() {
    const preferred = "video/webm;codecs=vp9,opus"
    return MediaRecorder.isTypeSupported(preferred) ? preferred : "video/webm"
  }

  // --- helpers ------------------------------------------------------------
  async postJSON(url, body) {
    const res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": this.csrfToken() },
      body: JSON.stringify(body)
    })
    if (!res.ok) {
      const data = await res.json().catch(() => ({}))
      throw new Error(data.error || res.statusText)
    }
    return res.json()
  }

  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content
  }

  toggle(recording) {
    if (this.hasStartTarget) this.startTarget.disabled = recording
    if (this.hasStopTarget) this.stopTarget.disabled = !recording
  }

  setStatus(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text
  }
}
