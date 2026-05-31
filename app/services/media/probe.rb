module Media
  # Thin ffprobe wrapper used by /complete to fill duration/mime (SPEC §7.2).
  module Probe
    module_function

    def duration_seconds(path)
      out = run(
        "-v", "error",
        "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1",
        path.to_s
      )
      out.to_f
    end

    # Returns { duration_seconds:, mime:, width:, height: }.
    def metadata(path)
      json = run(
        "-v", "error",
        "-print_format", "json",
        "-show_format", "-show_streams",
        path.to_s
      )
      data = JSON.parse(json)
      video = (data["streams"] || []).find { |s| s["codec_type"] == "video" } || {}
      {
        duration_seconds: data.dig("format", "duration").to_f,
        mime: mime_for(data.dig("format", "format_name")),
        width: video["width"],
        height: video["height"]
      }
    rescue JSON::ParserError
      { duration_seconds: 0.0, mime: "application/octet-stream", width: nil, height: nil }
    end

    def run(*args)
      out, err, status = Open3.capture3(Media.ffprobe_bin, *args)
      raise "ffprobe failed: #{err}" unless status.success?

      out
    end

    def mime_for(format_name)
      return "application/octet-stream" if format_name.blank?

      case format_name
      when /webm/ then "video/webm"
      when /mp4|mov/ then "video/mp4"
      when /matroska/ then "video/x-matroska"
      else "application/octet-stream"
      end
    end
  end
end
