module Transcription
  # Hosted STT with word/segment timestamps (SPEC §4, §9.3). Default real provider.
  # Sends the extracted mono 16 kHz audio and maps Deepgram's response onto the
  # provider contract.
  class Deepgram < Base
    ENDPOINT = "https://api.deepgram.com/v1/listen"

    def initialize(api_key: Scribe.config.deepgram_api_key)
      @api_key = api_key
    end

    def transcribe(audio_path:)
      raise "DEEPGRAM_API_KEY not set" if @api_key.blank?

      body = File.binread(audio_path)
      uri = URI(ENDPOINT)
      uri.query = URI.encode_www_form(
        model: "nova-2",
        smart_format: true,
        punctuate: true,
        paragraphs: true,
        utterances: true
      )

      req = Net::HTTP::Post.new(uri)
      req["Authorization"] = "Token #{@api_key}"
      req["Content-Type"] = "audio/flac"
      req.body = body

      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 600) { |h| h.request(req) }
      raise "Deepgram error #{res.code}: #{res.body}" unless res.code.to_i == 200

      parse(JSON.parse(res.body))
    end

    private

    def parse(payload)
      channel = payload.dig("results", "channels", 0) || {}
      alt = channel.dig("alternatives", 0) || {}

      # Prefer utterance-level segments; fall back to a single segment of words.
      segments =
        if payload.dig("results", "utterances").present?
          payload["results"]["utterances"].map do |u|
            { start_ms: (u["start"].to_f * 1000).round, end_ms: (u["end"].to_f * 1000).round, text: u["transcript"].to_s }
          end
        else
          words = alt["words"] || []
          [ {
            start_ms: ((words.first&.dig("start")).to_f * 1000).round,
            end_ms: ((words.last&.dig("end")).to_f * 1000).round,
            text: alt["transcript"].to_s
          } ]
        end

      {
        language: channel["detected_language"] || "en",
        full_text: alt["transcript"].to_s,
        segments:,
        raw: payload
      }
    end
  end
end
