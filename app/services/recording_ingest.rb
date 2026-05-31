# Ingests an *existing* video file (one the user already has) and runs the same
# pipeline as a live screen recording. Two entry points:
#
#   * from_upload — a multipart upload from the web "use an existing recording" form.
#   * from_path   — a local file path, used by the `scribe:ingest` CLI rake task.
#
# Unlike the live recorder, ingest skips the in-browser trim step and starts
# transcription immediately: the user already has the clip they want.
module RecordingIngest
  class Error < StandardError; end

  module_function

  # Process a file already on disk (CLI). When `inline:` is true the pipeline
  # runs synchronously (perform_now) so a one-shot CLI invocation produces
  # results without a separate worker process.
  def from_path(path, user: User.local, inline: false)
    path = path.to_s
    raise Error, "File not found: #{path}" unless File.file?(path)

    File.open(path, "rb") do |io|
      ingest(io, user:, filename: File.basename(path), content_type: mime_from_extension(path), inline:)
    end
  end

  # Process an uploaded file (web). The IO is the uploaded tempfile.
  def from_upload(user:, io:, filename:, content_type: nil)
    ingest(io, user:, filename:, content_type:, inline: false)
  end

  def ingest(io, user:, filename:, content_type:, inline:)
    recording = user.recordings.create!(status: :recording)
    ext = sanitized_extension(filename)
    storage_key = "recordings/#{recording.id}/source#{ext}"
    Storage.put(storage_key, io, content_type: content_type.presence || "application/octet-stream")

    meta = probe(storage_key)
    recording.update!(
      storage_key:,
      duration_seconds: meta[:duration_seconds],
      mime: meta[:mime].presence || content_type,
      status: :uploaded
    )

    if inline
      TranscribeJob.perform_now(recording.id)
    else
      TranscribeJob.perform_later(recording.id)
    end

    recording.reload
  end

  # Probe the stored file for duration/mime via ffprobe (best-effort).
  def probe(storage_key)
    local = Storage.local_path(storage_key)
    local ? Media::Probe.metadata(local) : { duration_seconds: 0.0, mime: nil }
  rescue StandardError => e
    Rails.logger.warn(tag: "recording_ingest", message: "probe failed: #{e.message}")
    { duration_seconds: 0.0, mime: nil }
  end

  def sanitized_extension(filename)
    ext = File.extname(filename.to_s).downcase
    ext =~ /\A\.[a-z0-9]{1,5}\z/ ? ext : ".webm"
  end

  def mime_from_extension(path)
    case File.extname(path).downcase
    when ".webm" then "video/webm"
    when ".mp4", ".m4v" then "video/mp4"
    when ".mov" then "video/quicktime"
    when ".mkv" then "video/x-matroska"
    end
  end
end
