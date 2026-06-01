require "net/http"
require "json"

module Transcription
  # Hosted STT via OpenAI's audio transcription API (SPEC §4, §9.3). Uploads the
  # extracted FLAC as multipart/form-data and requests verbose JSON so we get
  # segment-level timestamps.
  #
  # The HTTP call (#fetch) is separated from response mapping (#parse) so the
  # mapping is unit-testable offline.
  class Openai < Base
    ENDPOINT = "https://api.openai.com/v1/audio/transcriptions".freeze

    def initialize(api_key: Scribe.config.openai_api_key, model: Scribe.config.openai_transcribe_model)
      @api_key = api_key
      @model = model
    end

    def transcribe(audio_path:)
      raise ConfigurationError, "OPENAI_API_KEY not set" if @api_key.blank?

      parse(fetch(audio_path))
    end

    def fetch(audio_path)
      uri = URI(ENDPOINT)
      req = Net::HTTP::Post.new(uri)
      req["Authorization"] = "Bearer #{@api_key}"

      form = [
        [ "file", File.open(audio_path, "rb"), { filename: File.basename(audio_path), content_type: "audio/flac" } ],
        [ "model", @model ]
      ]
      # Only whisper-1 supports verbose_json with segment-level timestamps. The
      # gpt-4o-transcribe family rejects it and accepts only json/text, so we
      # request plain json there and let #parse fall back to a single segment.
      if segment_timestamps_supported?
        form << [ "response_format", "verbose_json" ]
        form << [ "timestamp_granularities[]", "segment" ]
      else
        form << [ "response_format", "json" ]
      end
      req.set_form(form, "multipart/form-data")

      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 600) { |h| h.request(req) }
      raise TranscriptionError, "OpenAI error #{res.code}: #{res.body}" unless res.code.to_i == 200

      JSON.parse(res.body)
    end

    # whisper-1 is the only OpenAI model that returns segment-level timestamps.
    def segment_timestamps_supported?
      @model.to_s.include?("whisper")
    end

    # Map an OpenAI verbose_json response onto the provider contract. Falls back
    # to a single segment when only plain text is returned.
    def parse(payload)
      segments =
        if payload["segments"].present?
          payload["segments"].map do |s|
            { start_ms: (s["start"].to_f * 1000).round, end_ms: (s["end"].to_f * 1000).round, text: s["text"].to_s.strip }
          end
        else
          [ { start_ms: 0, end_ms: (payload["duration"].to_f * 1000).round, text: payload["text"].to_s.strip } ]
        end

      {
        language: payload["language"] || "en",
        full_text: payload["text"].to_s.strip,
        segments:,
        raw: payload
      }
    end
  end
end
