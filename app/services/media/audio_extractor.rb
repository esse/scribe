module Media
  # Extracts narration audio for the STT provider (SPEC §8.2):
  #   ffmpeg -i input.webm -vn -ac 1 -ar 16000 -c:a flac audio.flac
  # Mono 16 kHz suits most STT engines and shrinks the provider upload.
  module AudioExtractor
    module_function

    def extract(input_path:, output_path:)
      out, err, status = Open3.capture3(
        Media.ffmpeg_bin, "-y",
        "-i", input_path.to_s,
        "-vn", "-ac", "1", "-ar", "16000",
        "-c:a", "flac",
        output_path.to_s
      )
      raise "ffmpeg audio extraction failed: #{err}" unless status.success?

      output_path
    end
  end
end
