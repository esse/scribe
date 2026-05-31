module Media
  # Server-side, non-destructive trimming for the in-browser editor.
  #
  # The browser never decodes or re-encodes the video — it only plays the source
  # over HTTP range requests and produces an *edit decision list*: the list of
  # time ranges (in seconds) to keep. That keeps the editor responsive on videos
  # of any length, including multi-hour recordings, since the client only ever
  # holds the bytes it's currently playing.
  #
  # Applying the edit happens here with ffmpeg using stream-copy (`-c copy`):
  # packets are copied without re-decoding, so a 2-hour recording is cut in
  # seconds with near-zero memory. We seek per segment, copy each to a temp file,
  # then concat. A single full-length segment is detected upstream and skipped
  # entirely (no ffmpeg work at all).
  module Editor
    module_function

    # Smallest keep-segment worth cutting; sub-100ms ranges are dropped as noise.
    MIN_SEGMENT_SECONDS = 0.1

    # Coerce arbitrary client input into a clean, ordered, non-overlapping list of
    # [start_s, end_s] float pairs, clamped to [0, duration]. Overlapping or
    # touching ranges are merged so concat never double-counts a region. Returns
    # [] when nothing valid remains.
    def normalize_segments(raw, duration_seconds:)
      duration = duration_seconds.to_f
      pairs = Array(raw).filter_map do |seg|
        s, e = segment_bounds(seg)
        next if s.nil? || e.nil?

        s = s.to_f.clamp(0.0, duration)
        e = e.to_f.clamp(0.0, duration)
        next if e - s < MIN_SEGMENT_SECONDS

        [ s.round(3), e.round(3) ]
      end

      merge(pairs.sort_by(&:first))
    end

    # True when the kept segments already cover essentially the whole recording,
    # so cutting would be a wasteful no-op. An empty list also means "keep all".
    def full_length?(segments, duration_seconds:)
      duration = duration_seconds.to_f
      return true if segments.blank? || duration <= 0

      segments.length == 1 &&
        segments.first[0] <= MIN_SEGMENT_SECONDS &&
        segments.first[1] >= duration - MIN_SEGMENT_SECONDS
    end

    # Total kept duration in seconds (drives credit metering on the edited video).
    def kept_duration(segments)
      segments.sum { |s, e| e - s }
    end

    # Cut the kept segments out of input_path and write a single video to
    # output_path. Stream-copy first; if a copy can't be produced (e.g. a codec
    # the concat demuxer rejects), fall back to a re-encode of just the kept
    # ranges so the edit still succeeds. Returns output_path.
    def cut(input_path:, output_path:, segments:)
      raise ArgumentError, "no segments to keep" if segments.blank?

      Dir.mktmpdir("scribe-edit") do |dir|
        parts = segments.each_with_index.map do |(start_s, end_s), i|
          part = File.join(dir, format("part_%03d%s", i, File.extname(output_path)))
          copy_segment(input_path:, output_path: part, start_s:, duration_s: end_s - start_s)
          part
        end

        if parts.length == 1
          FileUtils.mv(parts.first, output_path)
        else
          concat(parts:, output_path:, dir:)
        end
      end

      raise "ffmpeg produced no output" unless File.exist?(output_path) && File.size(output_path).positive?

      output_path
    end

    # --- internals ----------------------------------------------------------

    # Accepts [start, end], {"start"=>, "end"=>} or {start:, end:} shapes;
    # anything else yields [nil, nil] and is dropped by the caller.
    def segment_bounds(seg)
      if seg.is_a?(Array)
        [ seg[0], seg[1] ]
      elsif seg.is_a?(Hash) || seg.is_a?(ActionController::Parameters)
        [ seg["start"] || seg[:start], seg["end"] || seg[:end] ]
      else
        [ nil, nil ]
      end
    end

    def merge(sorted)
      sorted.each_with_object([]) do |(s, e), acc|
        last = acc.last
        if last && s <= last[1] + MIN_SEGMENT_SECONDS
          last[1] = [ last[1], e ].max
        else
          acc << [ s, e ]
        end
      end
    end

    # Input-seek (`-ss` before `-i`) + `-t` duration keeps copy fast and the cut
    # accurate to the nearest keyframe; `-avoid_negative_ts make_zero` rebases
    # timestamps so the concat demuxer stitches parts without gaps.
    def copy_segment(input_path:, output_path:, start_s:, duration_s:)
      run_or_reencode(
        copy_args: [
          "-ss", format("%.3f", start_s),
          "-i", input_path.to_s,
          "-t", format("%.3f", duration_s),
          "-c", "copy", "-avoid_negative_ts", "make_zero",
          output_path.to_s
        ],
        encode_args: [
          "-ss", format("%.3f", start_s),
          "-i", input_path.to_s,
          "-t", format("%.3f", duration_s),
          output_path.to_s
        ]
      )
    end

    def concat(parts:, output_path:, dir:)
      list = File.join(dir, "concat.txt")
      File.write(list, parts.map { |p| "file '#{p}'\n" }.join)
      run_or_reencode(
        copy_args: [ "-f", "concat", "-safe", "0", "-i", list, "-c", "copy", output_path.to_s ],
        encode_args: [ "-f", "concat", "-safe", "0", "-i", list, output_path.to_s ]
      )
    end

    # Try a stream-copy invocation; if ffmpeg fails or yields an empty file, retry
    # with a re-encode. Raises only when both fail.
    def run_or_reencode(copy_args:, encode_args:)
      return if ffmpeg(copy_args)

      raise "ffmpeg edit failed" unless ffmpeg(encode_args)
    end

    def ffmpeg(args)
      out_path = args.last
      _out, _err, status = Open3.capture3(Media.ffmpeg_bin, "-y", *args)
      status.success? && File.exist?(out_path) && File.size(out_path).positive?
    end
  end
end
