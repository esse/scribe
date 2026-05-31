module Media
  # Scene-detected + fallback frame extraction (SPEC §8.4) and on-demand seeks
  # (SPEC §8.5). Returns plain { timestamp_ms:, path: } hashes; persisting Frame
  # rows and uploading to storage is the job's concern.
  module FrameExtractor
    module_function

    # Candidate "step" frames for a recording. Scene-change detection first; if it
    # yields too few frames for the recording length, fall back to periodic
    # sampling so coverage is guaranteed. t=0 is always included.
    def extract(input_path:, out_dir:, threshold:, duration_seconds:,
                fallback_seconds: Scribe.config.fallback_sample_seconds)
      FileUtils.mkdir_p(out_dir)
      frames = scene_frames(input_path:, out_dir:, threshold:)

      expected_min = [ (duration_seconds.to_f / fallback_seconds).ceil, 1 ].max
      if frames.size < expected_min
        frames += periodic_frames(input_path:, out_dir:, interval: fallback_seconds, duration_seconds:)
      end

      # Always include the opening frame.
      frames << frame_at(input_path:, timestamp_ms: 0, out_dir:) unless frames.any? { |f| f[:timestamp_ms].zero? }

      dedupe(frames)
    end

    # ffmpeg scene filter + showinfo. showinfo logs one line per emitted frame to
    # stderr; the i-th line's pts_time maps to out_dir/0000(i+1).png (SPEC §8.4).
    def scene_frames(input_path:, out_dir:, threshold:)
      pattern = File.join(out_dir, "scene_%05d.png")
      # Coerce to a literal float; values reach ffmpeg as separate argv (no shell).
      filter = format("select='gt(scene,%.4f)',showinfo", threshold.to_f)
      _out, err, status = run_ffmpeg(
        "-y", "-i", input_path.to_s, "-vf", filter, "-vsync", "vfr", pattern
      )
      return [] unless status.success?

      times = err.scan(/pts_time:([0-9.]+)/).flatten.map { |t| (t.to_f * 1000).round }
      Dir.glob(File.join(out_dir, "scene_*.png")).sort.each_with_index.map do |path, i|
        { timestamp_ms: times[i] || 0, path: }
      end
    end

    # One frame per `interval` seconds, used to guarantee coverage (SPEC §8.4).
    def periodic_frames(input_path:, out_dir:, interval:, duration_seconds:)
      stops = (0..duration_seconds.to_i).step(interval).to_a
      stops.map { |sec| frame_at(input_path:, timestamp_ms: sec * 1000, out_dir:) }
    end

    # On-demand single-frame extraction at an exact time (SPEC §8.5):
    #   ffmpeg -ss <t> -i input.webm -frames:v 1 frame.png
    def frame_at(input_path:, timestamp_ms:, out_dir:, prefix: "ondemand")
      timestamp_ms = timestamp_ms.to_i
      out_path = File.join(out_dir, "#{prefix}_#{timestamp_ms}.png")
      seconds = format("%.3f", timestamp_ms / 1000.0)
      _out, err, status = run_ffmpeg(
        "-y", "-ss", seconds, "-i", input_path.to_s, "-frames:v", "1", out_path
      )
      raise "ffmpeg frame extraction failed at #{timestamp_ms}ms: #{err}" unless status.success? && File.exist?(out_path)

      { timestamp_ms:, path: out_path }
    end

    # Token-cost-control thumbnail for sending to Claude (SPEC §8.4, §9.4).
    def thumbnail(src_path:, out_path:, max_edge: Scribe.config.thumbnail_max_edge)
      scale = format("scale='min(%d,iw)':'-1':force_original_aspect_ratio=decrease", max_edge.to_i)
      _out, err, status = run_ffmpeg("-y", "-i", src_path.to_s, "-vf", scale, out_path.to_s)
      raise "ffmpeg thumbnail failed: #{err}" unless status.success?

      out_path
    end

    # Invoke ffmpeg, retrying once on a transient failure. Under heavy load
    # (e.g. many concurrent encodes) ffmpeg can occasionally be starved/killed;
    # a single retry makes extraction robust in production and CI alike.
    def run_ffmpeg(*args, attempts: 3)
      out = err = status = nil
      attempts.times do |i|
        out, err, status = Open3.capture3(Media.ffmpeg_bin, *args)
        return [ out, err, status ] if status.success?

        sleep(0.2 * (i + 1)) if i < attempts - 1
      end
      [ out, err, status ]
    end

    # Pixel dimensions of a still, for the frames row.
    def dimensions(path)
      meta = Media::Probe.metadata(path)
      [ meta[:width], meta[:height] ]
    end

    def dedupe(frames)
      frames.uniq { |f| f[:timestamp_ms] }.sort_by { |f| f[:timestamp_ms] }
    end
  end
end
