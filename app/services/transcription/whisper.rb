module Transcription
  # Self-hosted, cost-optimized swap (SPEC §4). Shells out to a faster-whisper
  # CLI that emits JSON with segment timestamps. Endpoint/binary are config so
  # this can also point at an HTTP wrapper.
  #
  # TODO(decision): confirm hosted (Deepgram) vs self-hosted faster-whisper.
  class Whisper < Base
    def initialize(bin: ENV.fetch("WHISPER_BIN", "faster-whisper"))
      @bin = bin
    end

    def transcribe(audio_path:)
      out, err, status = Open3.capture3(@bin, "--output_format", "json", "--language", "auto", audio_path.to_s)
      raise "whisper failed: #{err}" unless status.success?

      data = JSON.parse(out)
      segments = (data["segments"] || []).map do |s|
        { start_ms: (s["start"].to_f * 1000).round, end_ms: (s["end"].to_f * 1000).round, text: s["text"].to_s.strip }
      end

      {
        language: data["language"] || "en",
        full_text: data["text"].to_s.strip,
        segments:,
        raw: data
      }
    end
  end
end
