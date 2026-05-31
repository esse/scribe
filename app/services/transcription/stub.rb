module Transcription
  # Offline provider for dev/CI so the pipeline runs without external spend
  # (SPEC §15). Emits deterministic timed segments derived from the audio length
  # (or a fixed fixture transcript when one isn't probe-able).
  class Stub < Base
    SENTENCES = [
      "Open the dashboard from the main navigation.",
      "Click the New Project button in the top-right corner.",
      "Enter a name for your project and press Save.",
      "Your project now appears in the list of projects."
    ].freeze

    def transcribe(audio_path:)
      duration_ms = probe_duration_ms(audio_path)
      step = duration_ms.positive? ? duration_ms / SENTENCES.size : 3000
      segments = SENTENCES.each_with_index.map do |text, i|
        { start_ms: i * step, end_ms: (i + 1) * step, text: }
      end

      {
        language: "en",
        full_text: SENTENCES.join(" "),
        segments:,
        raw: { provider: "stub", duration_ms: }
      }
    end

    private

    def probe_duration_ms(audio_path)
      return 0 unless File.exist?(audio_path.to_s)

      out = Media::Probe.duration_seconds(audio_path)
      (out.to_f * 1000).round
    rescue StandardError
      0
    end
  end
end
