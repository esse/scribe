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

    # Select the configured provider (SPEC §9.3). Real hosted providers (Deepgram,
    # OpenAI) and a local CLI (whisper) are available; defaults to the offline stub
    # so dev/CI never spend on external STT. An unknown name is a hard error rather
    # than a silent fallback.
    def self.build(name = Scribe.config.transcription_provider)
      case name.to_s
      when "deepgram" then Transcription::Deepgram.new
      when "openai"   then Transcription::Openai.new
      when "whisper"  then Transcription::Whisper.new
      when "stub", "" then Transcription::Stub.new
      else raise ConfigurationError, "Unknown TRANSCRIPTION_PROVIDER: #{name.inspect}"
      end
    end
  end
end
