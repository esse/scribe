module Transcription
  # Provider-abstracted speech-to-text (SPEC §2, §9.3). The Anthropic API has no
  # STT capability, so transcription always goes through a dedicated provider.
  #
  # Implementations MUST return segment-level timestamps:
  #   { language:, full_text:, segments: [{ start_ms:, end_ms:, text: }], raw: }
  class Base
    def transcribe(audio_path:)
      raise NotImplementedError, "#{self.class} must implement #transcribe"
    end

    # Select the configured provider (SPEC §9.3). Defaults to the offline stub so
    # dev/CI never spend on external STT.
    def self.build
      case Scribe.config.transcription_provider.to_s
      when "deepgram" then Transcription::Deepgram.new
      when "whisper"  then Transcription::Whisper.new
      else Transcription::Stub.new
      end
    end
  end
end
